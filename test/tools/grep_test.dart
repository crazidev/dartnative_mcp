// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:dartnative_mcp/src/mixins/grep_packages.dart';
import 'package:dartnative_mcp/src/mixins/package_uri_reader.dart';
import 'package:dartnative_mcp/src/utils/names.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

void main() {
  late TestHarness testHarness;
  late Root dartAppRoot;

  Future<CallToolResult> grep({
    required List<String> packageNames,
    required List<String> arguments,
    String? searchDir,
    bool expectError = false,
  }) {
    final args = <String, Object?>{
      ParameterNames.root: dartAppRoot.uri,
      ParameterNames.packageNames: packageNames,
      ParameterNames.arguments: arguments,
    };
    if (searchDir != null) {
      args[ParameterNames.searchDir] = searchDir;
    }
    return testHarness.callTool(
      CallToolRequest(
        name: GrepSupport.ripGrepPackagesTool.name,
        arguments: args,
      ),
      expectError: expectError,
    );
  }

  setUpAll(() async {
    testHarness = await TestHarness.start(
      inProcess: true,
      processManager: const LocalProcessManager(),
    );
    // Allow it to install ripgrep if necessary.
    testHarness.mcpClient.registerElicitationHandler(
      (_) => ElicitResult(action: ElicitationAction.accept),
    );
    dartAppRoot = testHarness.rootForPath(dartAppPath);
    testHarness.mcpClient.addRoot(dartAppRoot);
  });

  group('RipGrepSupport', () {
    test('finds matches in project files', () async {
      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-e', r'void main\('],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:dart_app/main.dart'));
      expect(content.text, contains('void main('));
    });

    test('finds matches with glob pattern', () async {
      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-g', '*.dart', '-e', 'class Greeter'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:dart_app/main.dart'));
      expect(content.text, contains('class Greeter'));
    });

    test('finds matches in package dependencies', () async {
      final result = await grep(
        packageNames: ['path'],
        arguments: ['-e', 'class Context'],
      );

      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(content.text, contains('package:path/src/context.dart'));
    });

    test('supports case insensitive search', () async {
      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-i', '-e', r'VOID MAIN\('],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package:dart_app/main.dart'));
    });

    test('returns a good message when package not found', () async {
      final result = await grep(
        packageNames: ['non_existent_package'],
        arguments: ['-e', 'class Widget'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(
        content.text,
        contains(packageNotFoundText('non_existent_package').text),
      );
    });

    test('returns a good message when no matches found', () async {
      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-e', 'non_existent_class'],
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;
      expect(content.text, contains('No matches in package `dart_app`'));
    });

    test('can search outside of lib/ when searchDir is empty string', () async {
      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-e', 'name: dart_app'],
        searchDir: '',
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      expect(content.text, contains('package-root:dart_app/pubspec.yaml'));
    });

    test('can search in specific directory', () async {
      final server = testHarness.serverConnectionPair.server!;
      final testDir = server.fileSystem.directory(
        Uri.parse(dartAppRoot.uri).resolve('grep_test/').toFilePath(),
      );
      addTearDown(() => testDir.delete(recursive: true));
      testDir.createSync(recursive: true);
      final testFile = server.fileSystem.file(
        testDir.uri.resolve('dummy_test.dart').toFilePath(),
      );
      testFile.writeAsStringSync('void main() { print("dummy test"); }');

      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-e', 'dummy test'],
        searchDir: 'grep_test', // search specifically in "grep_test"
      );
      expect(result.isError, isNot(isTrue));
      final content = result.content.first as TextContent;

      // Results outside lib use package-root:
      expect(
        content.text,
        contains('package-root:dart_app/grep_test/dummy_test.dart'),
      );
      expect(content.text, contains('dummy test'));
    });

    test('refuses to search outside package root', () async {
      final result = await grep(
        packageNames: ['dart_app'],
        arguments: ['-e', 'dummy test'],
        searchDir: '../', // try to escape the root
      );
      expect(result.isError, isNot(isTrue)); // we return content with the error
      final content = result.content.first as TextContent;

      expect(
        content.text,
        contains('attempted to escape the root of package `dart_app`'),
      );
    });
  });

  test('rejects arbitrary ripgrep flags', () async {
    final result = await grep(
      packageNames: ['dart_app'],
      arguments: ['--pre', 'echo', '-e', 'void main'],
      expectError: true,
    );
    expect(result.isError, isTrue);
    final content = result.content.first as TextContent;
    expect(
      content.text,
      contains(
        'Refusing to run ripgrep: the following arguments are not permitted: '
        '--pre, echo',
      ),
    );
  });
  test('Can install ripgrep', () async {
    final server = testHarness.serverConnectionPair.server!;
    final tmpDir = server.fileSystem.systemTempDirectory.createTempSync(
      'rip-grep-test',
    );
    try {
      final installPath = await server.tryInstallRipGrep(installDir: tmpDir);
      expect(installPath, isNotNull);
      final executable = server.fileSystem.file(installPath);
      expect(executable.existsSync(), isTrue);
      expect(executable.statSync().modeString(), contains('x'));
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  });
}
