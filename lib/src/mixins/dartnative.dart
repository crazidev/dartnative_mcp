// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A mixin that provides tools backed by the DartNative `dn` CLI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';

import '../features_configuration.dart';
import '../utils/analytics.dart';
import '../utils/cli_utils.dart';
import '../utils/file_system.dart';
import '../utils/names.dart';
import '../utils/process_manager.dart';
import '../utils/sdk.dart';

class _RunningDnApp {
  _RunningDnApp(this.process, this.root);

  final Process process;
  final String root;
  final List<String> logs = [];
  bool exited = false;
}

/// A mixin that provides tools backed by the DartNative `dn` CLI.
///
/// These tools are only registered when a DartNative SDK (and therefore `dn`)
/// can be found.
base mixin DartNativeCliSupport
    on ToolsSupport, LoggingSupport, RootsTrackingSupport
    implements ProcessManagerSupport, SdkSupport, FileSystemSupport {
  final Map<int, _RunningDnApp> _runningApps = {};

  static const Set<String> _allowedRunFlags = {
    '--debug',
    '--profile',
    '--release',
    '--flavor',
    '--dart-define',
    '--verbose',
    '-v',
    '--dart-entrypoint-args',
    '-a',
    '--hot',
    '--no-hot',
    '--pub',
    '--no-pub',
  };

  static const Set<String> _managedRunFlags = {
    '--device-id',
    '-d',
    '--target',
    '-t',
    '--machine',
    '--pid-file',
    '--vmservice-out-file',
    '--use-application-binary',
  };

  static const Set<String> _buildTargets = {
    'aar',
    'apk',
    'appbundle',
    'bundle',
    'ios',
    'ipa',
    'linux',
    'macos',
    'web',
    'windows',
  };

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    try {
      return super.initialize(request);
    } finally {
      if (sdk.hasDartNative) {
        registerTool(dnAnalyzeTool, _runDnAnalyze);
        registerTool(dnBuildTool, _runDnBuild);
        registerTool(dnCleanTool, _runDnClean);
        registerTool(dnDevicesTool, _runDnDevices);
        registerTool(dnDoctorTool, _runDnDoctor);
        registerTool(dnInstallTool, _runDnInstall);
        registerTool(dnRunTool, _runDnRun);
        registerTool(dnStopAppTool, _stopDnApp);
        registerTool(dnAppLogsTool, _getDnAppLogs);
      }
    }
  }

  @visibleForTesting
  static final List<Tool> allTools = [
    dnAnalyzeTool,
    dnBuildTool,
    dnCleanTool,
    dnDevicesTool,
    dnDoctorTool,
    dnInstallTool,
    dnRunTool,
    dnStopAppTool,
    dnAppLogsTool,
  ];

  /// Implementation of the [dnAnalyzeTool].
  Future<CallToolResult> _runDnAnalyze(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      commandForRoot: (_, _, sdk) => sdk.dnExecutablePath,
      arguments: ['analyze'],
      commandDescription: 'dn analyze',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [dnBuildTool].
  Future<CallToolResult> _runDnBuild(CallToolRequest request) async {
    final target =
        request.arguments![ParameterNames.target] as String? ?? 'apk';
    if (!_buildTargets.contains(target)) {
      return _argumentError(
        'Unsupported build target `$target`. Supported targets are: '
        '${_buildTargets.join(', ')}.',
      );
    }
    final extraArgs =
        (request.arguments![ParameterNames.arguments] as List?)
            ?.cast<String>() ??
        const <String>[];
    final invalidArgs = extraArgs.where(
      (arg) => arg.startsWith('-') && !_allowedRunFlags.contains(arg),
    );
    if (invalidArgs.isNotEmpty) {
      return _argumentError(
        'The `arguments` parameter contains unsupported build options: '
        '${invalidArgs.map((a) => '`$a`').join(', ')}.',
      );
    }
    return runCommandInRoots(
      request,
      commandForRoot: (_, _, sdk) => sdk.dnExecutablePath,
      arguments: ['build', target, ...extraArgs],
      commandDescription: 'dn build $target',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [dnCleanTool].
  Future<CallToolResult> _runDnClean(CallToolRequest request) async {
    return runCommandInRoots(
      request,
      commandForRoot: (_, _, sdk) => sdk.dnExecutablePath,
      arguments: ['clean'],
      commandDescription: 'dn clean',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [dnDevicesTool].
  Future<CallToolResult> _runDnDevices(CallToolRequest request) async {
    return _runGlobalDnCommand(['devices'], commandDescription: 'dn devices');
  }

  /// Implementation of the [dnDoctorTool].
  Future<CallToolResult> _runDnDoctor(CallToolRequest request) async {
    return _runGlobalDnCommand(['doctor'], commandDescription: 'dn doctor');
  }

  /// Implementation of the [dnInstallTool].
  Future<CallToolResult> _runDnInstall(CallToolRequest request) async {
    final device = request.arguments![ParameterNames.device] as String?;
    return runCommandInRoots(
      request,
      commandForRoot: (_, _, sdk) => sdk.dnExecutablePath,
      arguments: [
        'install',
        if (device != null) ...['-d', device],
      ],
      commandDescription: 'dn install',
      processManager: processManager,
      knownRoots: await roots,
      fileSystem: fileSystem,
      sdk: sdk,
    );
  }

  /// Implementation of the [dnRunTool].
  Future<CallToolResult> _runDnRun(CallToolRequest request) async {
    final validation = validateRootConfig(
      request.arguments,
      fileSystem: fileSystem,
      knownRoots: await roots,
    );
    if (validation.errorResult != null) return validation.errorResult!;
    final root = fileSystem.directory(Uri.parse(validation.root!.uri)).path;

    final device = request.arguments![ParameterNames.device] as String?;
    if (device == null || device.isEmpty) {
      return _argumentError('The `device` parameter is required.');
    }
    final target = request.arguments![ParameterNames.target] as String?;
    final extraArgs =
        (request.arguments![ParameterNames.arguments] as List?)
            ?.cast<String>() ??
        const <String>[];
    final blockedArgs = extraArgs.where(
      (arg) =>
          _managedRunFlags.any(
            (flag) => arg == flag || arg.startsWith('$flag='),
          ) ||
          (arg.startsWith('-') && !_allowedRunFlags.contains(arg)),
    );
    if (blockedArgs.isNotEmpty) {
      return _argumentError(
        'The `arguments` parameter contains disallowed `dn run` options: '
        '${blockedArgs.map((a) => '`$a`').join(', ')}. Use the `device` and '
        '`target` parameters for device/entrypoint selection.',
      );
    }
    final timeout = request.arguments![ParameterNames.timeout] as int? ?? 90000;

    final ready = Completer<String?>();
    final Process process;
    try {
      process = await processManager.start(
        [
          sdk.dnExecutablePath,
          'run',
          '-d',
          device,
          if (target != null) ...['-t', target],
          ...extraArgs,
        ],
        workingDirectory: root,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      return _argumentError('Failed to start `dn run`: $e');
    }

    final app = _RunningDnApp(process, root);
    _runningApps[process.pid] = app;

    void onLine(String prefix, String line) {
      app.logs.add('[$prefix] $line');
      log(LoggingLevel.debug, '[dn $prefix ${process.pid}]: $line');
      if (ready.isCompleted) return;
      if (line.contains('Dart VM Service') ||
          line.contains('run key commands') ||
          line.contains('Syncing files to device') ||
          line.contains('is available at:')) {
        ready.complete('started');
      } else if (line.contains('Error launching application') ||
          line.contains('Could not build') ||
          line.contains('Failed to install') ||
          line.contains('No devices found')) {
        ready.complete(null);
      }
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLine('stdout', line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLine('stderr', line));

    unawaited(
      process.exitCode.then((exitCode) {
        app.exited = true;
        log(
          LoggingLevel.info,
          'DartNative application ${process.pid} exited with code $exitCode.',
        );
        if (!ready.isCompleted) ready.complete(null);
      }),
    );

    String? startup;
    try {
      startup = await ready.future.timeout(Duration(milliseconds: timeout));
    } on TimeoutException {
      startup = 'timeout';
    }

    final summary = {
      ParameterNames.pid: process.pid,
      ParameterNames.root: root,
      ParameterNames.ready: startup == 'started',
      'exited': app.exited,
      'logs': _tail(app.logs, 100),
    };
    final text = const JsonEncoder.withIndent('  ').convert(summary);
    if (startup == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'The application exited before it was ready to receive hot '
                'reloads.\n\n$text',
          ),
        ],
        isError: true,
      )..failureReason = CallToolFailureReason.noSuchCommand;
    }
    return CallToolResult(
      content: [
        TextContent(
          text: startup == 'timeout'
              ? 'The application did not report readiness within '
                    '${timeout}ms. It is still running; use '
                    '`${ToolNames.dnAppLogs.name}` to read more output.\n\n'
                    '$text'
              : 'DartNative application started.\n\n$text',
        ),
      ],
    );
  }

  /// Implementation of the [dnStopAppTool].
  Future<CallToolResult> _stopDnApp(CallToolRequest request) async {
    final pid = request.arguments![ParameterNames.pid] as int;
    final app = _runningApps[pid];
    if (app == null) {
      return _argumentError('No running application with PID $pid.');
    }
    app.process.kill();
    _runningApps.remove(pid);
    return CallToolResult(
      content: [TextContent(text: 'Stopped application with PID $pid.')],
    );
  }

  /// Implementation of the [dnAppLogsTool].
  Future<CallToolResult> _getDnAppLogs(CallToolRequest request) async {
    final pid = request.arguments![ParameterNames.pid] as int;
    final lines = request.arguments![ParameterNames.lines] as int? ?? 200;
    final app = _runningApps[pid];
    if (app == null) {
      return _argumentError('No running application with PID $pid.');
    }
    return CallToolResult(
      content: [TextContent(text: _tail(app.logs, lines).join('\n'))],
    );
  }

  Future<CallToolResult> _runGlobalDnCommand(
    List<String> arguments, {
    required String commandDescription,
  }) async {
    final ProcessResult result;
    try {
      result = await processManager.run([
        sdk.dnExecutablePath,
        ...arguments,
      ], workingDirectory: fileSystem.currentDirectory.path);
    } on ProcessException catch (e) {
      return _argumentError('Failed to run `$commandDescription`: $e');
    }
    final output = (result.stdout as String).trim();
    final errors = (result.stderr as String).trim();
    return CallToolResult(
      content: [
        TextContent(
          text:
              '$commandDescription:\n'
              '$output${errors.isEmpty ? '' : '\nErrors:\n$errors'}',
        ),
      ],
      isError: result.exitCode != 0,
    );
  }

  static List<String> _tail(List<String> logs, int count) {
    final start = math.max(0, logs.length - count);
    return logs.sublist(start);
  }

  static CallToolResult _argumentError(String message) =>
      CallToolResult(content: [TextContent(text: message)], isError: true)
        ..failureReason = CallToolFailureReason.argumentError;

  static final dnAnalyzeTool =
      Tool(
          name: ToolNames.dnAnalyze.name,
          description:
              'Runs `dn analyze` for the given project roots. Prefer '
              '`${ToolNames.analyzeFiles.name}` for structured diagnostics; '
              'use '
              'this when you specifically want the DartNative analyzer output.',
          annotations: ToolAnnotations(title: 'dn analyze'),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.roots: rootsSchema(supportsPaths: true),
            },
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnBuildTool =
      Tool(
          name: ToolNames.dnBuild.name,
          description:
              'Runs `dn build <target>` for the given project roots, for '
              'example `dn build apk` or `dn build macos`.',
          annotations: ToolAnnotations(
            title: 'dn build',
            destructiveHint: true,
          ),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.roots: rootsSchema(),
              ParameterNames.target: Schema.string(
                description:
                    'The build target, one of: ${_buildTargets.join(', ')}. '
                    'Defaults to `apk`.',
              ),
              ParameterNames.arguments: Schema.list(
                items: Schema.string(),
                description: 'Additional arguments to pass to `dn build`.',
              ),
            },
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnCleanTool =
      Tool(
          name: ToolNames.dnClean.name,
          description: 'Runs `dn clean` for the given project roots.',
          annotations: ToolAnnotations(
            title: 'dn clean',
            destructiveHint: true,
          ),
          inputSchema: Schema.object(
            properties: {ParameterNames.roots: rootsSchema()},
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnDevicesTool =
      Tool(
          name: ToolNames.dnDevices.name,
          description:
              'Runs `dn devices` and returns the connected devices and '
              'emulators that `dn run` can target.',
          annotations: ToolAnnotations(title: 'dn devices'),
          inputSchema: Schema.object(
            properties: {},
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnDoctorTool =
      Tool(
          name: ToolNames.dnDoctor.name,
          description: 'Runs `dn doctor` and returns the tooling diagnostics.',
          annotations: ToolAnnotations(title: 'dn doctor'),
          inputSchema: Schema.object(
            properties: {},
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnInstallTool =
      Tool(
          name: ToolNames.dnInstall.name,
          description:
              'Runs `dn install` for the given project roots, optionally on a '
              'specific device.',
          annotations: ToolAnnotations(
            title: 'dn install',
            destructiveHint: true,
          ),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.roots: rootsSchema(),
              ParameterNames.device: Schema.string(
                description:
                    'The device ID to install on. Use '
                    '`${ToolNames.dnDevices.name}` to list devices.',
              ),
            },
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnRunTool =
      Tool(
          name: ToolNames.dnRun.name,
          description:
              'Runs `dn run` for the given project root on a device. Returns '
              'the process ID and the startup logs. The app keeps running so '
              'you can read logs and stop it later.',
          annotations: ToolAnnotations(title: 'dn run'),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.root: rootSchema,
              ParameterNames.device: Schema.string(
                description:
                    'The device ID to run on. Use '
                    '`${ToolNames.dnDevices.name}` to list devices.',
              ),
              ParameterNames.target: Schema.string(
                description:
                    'The main entry point file of the application. Defaults to '
                    'the project default (usually `bin/main.dart`).',
              ),
              ParameterNames.arguments: Schema.list(
                items: Schema.string(),
                description:
                    'Additional arguments to pass to `dn run`, for example '
                    '["--dart-define=KEY=value"].',
              ),
              ParameterNames.timeout: Schema.int(
                description:
                    'How long to wait for the app to start, in milliseconds. '
                    'Defaults to 90000.',
              ),
            },
            required: [ParameterNames.root, ParameterNames.device],
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnStopAppTool =
      Tool(
          name: ToolNames.dnStopApp.name,
          description:
              'Stops an application started with `${ToolNames.dnRun.name}`.',
          annotations: ToolAnnotations(title: 'dn stop', destructiveHint: true),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.pid: Schema.int(
                description: 'The process ID returned by `dn_run`.',
              ),
            },
            required: [ParameterNames.pid],
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;

  static final dnAppLogsTool =
      Tool(
          name: ToolNames.dnAppLogs.name,
          description:
              'Returns the log output of an application started with '
              '`${ToolNames.dnRun.name}`.',
          annotations: ToolAnnotations(title: 'dn logs'),
          inputSchema: Schema.object(
            properties: {
              ParameterNames.pid: Schema.int(
                description: 'The process ID returned by `dn_run`.',
              ),
              ParameterNames.lines: Schema.int(
                description:
                    'The maximum number of trailing log lines to return. '
                    'Defaults to 200.',
              ),
            },
            required: [ParameterNames.pid],
            additionalProperties: false,
          ),
        )
        ..categories = [FeatureCategory.dartnative, FeatureCategory.cli]
        ..enabledByDefault = false;
}
