// Copyright (c) 2026, the Dart project authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Runs the `install` subcommand.
///
/// Returns the process exit code.
Future<int> runInstall(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ides', help: 'Comma-separated IDE ids to configure (e.g. vscode,cursor).')
    ..addFlag('all', help: 'Configure every detected IDE.', defaultsTo: false)
    ..addFlag('detected', help: 'Configure only the detected IDEs.', defaultsTo: false)
    ..addOption('dn-sdk', help: 'Path to the DartNative SDK root.')
    ..addOption('dart-sdk', help: 'Path to the Dart SDK root.')
    ..addFlag('help', abbr: 'h', help: 'Show this help.', defaultsTo: false);

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    return 64;
  }
  if (parsed.flag('help')) {
    stdout.writeln('Usage: dartnative_mcp install [options]');
    stdout.writeln('');
    stdout.writeln('Installs the DartNative MCP server into the current project by');
    stdout.writeln('writing MCP client configuration for the selected IDEs and');
    stdout.writeln('copying the agent skill.');
    stdout.writeln('');
    stdout.writeln(parser.usage);
    stdout.writeln('');
    stdout.writeln('IDE ids: vscode, cursor, claude, gemini, opencode, antigravity, chatgpt');
    return 0;
  }

  final projectDir = Directory.current.path;
  final packageRoot = _findPackageRoot();
  final dnSdkPath = parsed.option('dn-sdk') ?? Platform.environment['DN_ROOT'] ?? Platform.environment['DARTNATIVE_ROOT'];
  final dartBinary = parsed.option('dart-sdk') != null
      ? p.join(parsed.option('dart-sdk')!, 'bin', Platform.isWindows ? 'dart.exe' : 'dart')
      : Platform.resolvedExecutable;

  final ideTargets = <_IdeTarget>[
    _IdeTarget('vscode', 'VS Code', '.vscode', p.join('.vscode', 'mcp.json'), 'vscode'),
    _IdeTarget('cursor', 'Cursor', '.cursor', p.join('.cursor', 'mcp.json'), 'mcpServers'),
    _IdeTarget('claude', 'Claude Code', '.claude', '.mcp.json', 'mcpServers'),
    _IdeTarget('gemini', 'Gemini CLI', '.gemini', p.join('.gemini', 'settings.json'), 'mcpServers'),
    _IdeTarget('opencode', 'OpenCode', '.', 'opencode.json', 'opencode'),
    _IdeTarget('antigravity', 'Antigravity', '.antigravity', p.join('.antigravity', 'mcp.json'), 'mcpServers'),
    _IdeTarget('chatgpt', 'ChatGPT', '.chatgpt', p.join('.chatgpt', 'mcp.json'), 'mcpServers'),
  ];

  bool isDetected(_IdeTarget ide) {
    if (ide.detectFolder == '.') {
      return File(p.join(projectDir, ide.configPath)).existsSync();
    }
    return Directory(p.join(projectDir, ide.detectFolder)).existsSync() ||
        File(p.join(projectDir, ide.configPath)).existsSync();
  }

  final detected = ideTargets.where(isDetected).toList();

  Set<String> selectedIds;
  final idesOption = parsed.option('ides');
  if (parsed.flag('all')) {
    selectedIds = ideTargets.map((i) => i.id).toSet();
  } else if (parsed.flag('detected')) {
    selectedIds = detected.map((i) => i.id).toSet();
  } else if (idesOption != null && idesOption.trim().isNotEmpty) {
    selectedIds = idesOption.split(',').map((s) => s.trim()).toSet();
  } else {
    // Interactive selection.
    stdout.writeln('Detected IDEs:');
    for (final ide in detected) stdout.writeln('  * ${ide.label}');
    stdout.writeln('');
    stdout.writeln('Available IDEs:');
    for (var i = 0; i < ideTargets.length; i++) {
      final ide = ideTargets[i];
      final mark = detected.contains(ide) ? '*' : ' ';
      stdout.writeln('  ${i + 1}. [$mark] ${ide.label} (${ide.id})');
    }
    stdout.write('Select IDEs (comma-separated numbers, "all", or "detected"; default: detected): ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.isEmpty || input.toLowerCase() == 'detected') {
      selectedIds = detected.map((i) => i.id).toSet();
    } else if (input.toLowerCase() == 'all') {
      selectedIds = ideTargets.map((i) => i.id).toSet();
    } else {
      selectedIds = <String>{};
      for (final part in input.split(',')) {
        final idx = int.tryParse(part.trim());
        if (idx != null && idx >= 1 && idx <= ideTargets.length) {
          selectedIds.add(ideTargets[idx - 1].id);
        }
      }
    }
  }

  if (selectedIds.isEmpty) {
    stdout.writeln('No IDEs selected. Nothing to do.');
    return 0;
  }

  // Write launcher.
  final launcherDir = Directory(p.join(projectDir, '.dartnative'));
  launcherDir.createSync(recursive: true);
  final isWin = Platform.isWindows;
  final launcherPath = isWin
      ? p.join(projectDir, '.dartnative', 'mcp.bin.cmd')
      : p.join(projectDir, '.dartnative', 'mcp.bin');
  final dnArg = dnSdkPath != null ? ' --dn-sdk ${_sh(dnSdkPath)}' : '';
  if (isWin) {
    final pubCacheWin = Platform.environment['PUB_CACHE'];
    final pubCacheLineWin = (pubCacheWin != null && pubCacheWin.trim().isNotEmpty)
        ? 'set "PUB_CACHE=${pubCacheWin}"\r\n'
        : '';
    File(launcherPath).writeAsStringSync(
      '@echo off\r\n'
      'REM Generated by DartNative: Install MCP Server. Do not edit.\r\n'
      '$pubCacheLineWin'
      '"$dartBinary" pub global run dartnative_mcp$dnArg --enable cli %*\r\n',
    );
  } else {
    final pubCache = Platform.environment['PUB_CACHE'];
    final pubCacheLine = (pubCache != null && pubCache.trim().isNotEmpty)
        ? 'export PUB_CACHE=${_sh(pubCache)}\n'
        : '';
    File(launcherPath).writeAsStringSync(
      '#!/bin/sh\n'
      '# Generated by DartNative: Install MCP Server. Do not edit.\n'
      '$pubCacheLine'
      'exec ${_sh(dartBinary)} pub global run dartnative_mcp$dnArg --enable cli "\$@"\n',
    );
    Process.runSync('chmod', ['+x', launcherPath]);
  }

  final launchCommand = isWin ? (Platform.environment['ComSpec'] ?? 'cmd.exe') : launcherPath;
  final launchArgs = isWin ? <String>['/c', launcherPath] : <String>[];

  // Write configs.
  final written = <String>[];
  for (final ide in ideTargets.where((i) => selectedIds.contains(i.id))) {
    final file = File(p.join(projectDir, ide.configPath));
    file.parent.createSync(recursive: true);
    Map<String, dynamic> json = {};
    if (file.existsSync()) {
      try {
        json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        stderr.writeln('Skipped ${ide.configPath}: invalid JSON.');
        continue;
      }
    }
    if (ide.format == 'vscode') {
      json['servers'] ??= <String, dynamic>{};
      (json['servers'] as Map<String, dynamic>)[serverName] = {
        'type': 'stdio',
        'command': launchCommand,
        'args': launchArgs,
      };
    } else if (ide.format == 'opencode') {
      json['mcp'] ??= <String, dynamic>{};
      (json['mcp'] as Map<String, dynamic>)[serverName] = {
        'type': 'local',
        'command': <String>[launchCommand, ...launchArgs],
        'enabled': true,
      };
    } else {
      json['mcpServers'] ??= <String, dynamic>{};
      (json['mcpServers'] as Map<String, dynamic>)[serverName] = {
        'command': launchCommand,
        'args': launchArgs,
      };
    }
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
    written.add(ide.configPath);
  }

  // Copy skills.
  final skillSource = File(p.join(packageRoot, 'skills', skillName, 'SKILL.md'));
  final skillTargets = <String>[
    p.join('.agents', 'skills', skillName),
    p.join('.cursor', 'skills', skillName),
    p.join('.claude', 'skills', skillName),
  ];
  if (skillSource.existsSync()) {
    for (final target in skillTargets) {
      final dir = Directory(p.join(projectDir, target));
      dir.createSync(recursive: true);
      File(p.join(projectDir, target, 'SKILL.md')).writeAsStringSync(skillSource.readAsStringSync());
    }
  }

  // Summary.
  stdout.writeln('');
  stdout.writeln('DartNative MCP server installed.');
  stdout.writeln('  Source: ${packageRoot}');
  stdout.writeln('  Launcher: ${isWin ? '.dartnative\\mcp.bin.cmd' : '.dartnative/mcp.bin'}');
  stdout.writeln('  IDEs: ${selectedIds.join(', ')}');
  for (final f in written) stdout.writeln('  Config: $f');
  stdout.writeln('  Skills: ${skillTargets.map((t) => '$t/SKILL.md').join(', ')}');
  stdout.writeln('Restart your MCP client to connect.');
  return 0;
}

String _findPackageRoot() {
  try {
    final script = File(Platform.script.toFilePath());
    // bin/dartnative_mcp.dart -> package root
    final binDir = script.parent;
    if (File(p.join(binDir.path, 'dartnative_mcp.dart')).existsSync() ||
        File(p.join(binDir.path, 'dartnative_mcp')).existsSync()) {
      return binDir.parent.path;
    }
    // global snapshot: walk up until skills/dartnative-mcp/SKILL.md exists
    var dir = binDir;
    for (var i = 0; i < 6; i++) {
      if (File(p.join(dir.path, 'skills', 'dartnative-mcp', 'SKILL.md')).existsSync()) {
        return dir.path;
      }
      dir = dir.parent;
    }
  } catch (_) {}
  return Directory.current.path;
}

String _sh(String value) => "'${value.replaceAll("'", "'\\''")}'";

class _IdeTarget {
  final String id;
  final String label;
  final String detectFolder;
  final String configPath;
  final String format;
  _IdeTarget(this.id, this.label, this.detectFolder, this.configPath, this.format);
}

const serverName = 'dartnative';
const skillName = 'dartnative-mcp';