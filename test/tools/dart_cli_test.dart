// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dartnative_mcp/src/features_configuration.dart';
import 'package:dartnative_mcp/src/mixins/dash_cli.dart';
import 'package:dartnative_mcp/src/utils/names.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../test_harness.dart';

void main() {
  test('cli tools are disabled by default', () async {
    final featureConfig = const FeaturesConfiguration();
    for (var tool in DashCliSupport.allTools) {
      expect(
        featureConfig.isEnabled(
          tool.name,
          tool.enabledByDefault,
          tool.categories,
        ),
        isFalse,
        reason: 'Tool ${tool.name} should be disabled by default',
      );
    }
  });

  group('when cli features are enabled', () {
    late TestHarness testHarness;
    late TestProcessManager testProcessManager;
    late Root exampleDartNativeAppRoot;
    late Root dartCliAppRoot;
    final dartExecutableName = 'dart${Platform.isWindows ? '.exe' : ''}';
    final dnExecutableName = 'dn${Platform.isWindows ? '.bat' : ''}';
    late Tool dartFixTool;
    late Tool dartFormatTool;
    late Tool createProjectTool;

    // TODO: Use setUpAll, currently this fails due to an apparent TestProcess
    // issue.
    setUp(() async {
      testHarness = await TestHarness.start(
        inProcess: true,
        // Enable all cli features so we can test them.
        featuresConfig: FeaturesConfiguration(
          enabledNames: {FeatureCategory.cli.name},
        ),
      );
      testProcessManager =
          testHarness.serverConnectionPair.server!.processManager
              as TestProcessManager;

      final dartNativeExample = d.dir('dartnative_example', [
        d.file('pubspec.yaml', '''
name: dartnative_example
environment:
  sdk: ^3.0.0
dependencies:
  dartnative: ^1.0.0
'''),
      ]);
      await dartNativeExample.create();

      exampleDartNativeAppRoot = testHarness.rootForPath(
        dartNativeExample.io.path,
      );
      dartCliAppRoot = testHarness.rootForPath(dartCliAppsPath);

      await pumpEventQueue();

      final tools = (await testHarness.mcpServerConnection.listTools()).tools;
      dartFixTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.dartFixTool.name,
      );
      dartFormatTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.dartFormatTool.name,
      );
      createProjectTool = tools.singleWhere(
        (t) => t.name == DashCliSupport.createProjectTool.name,
      );
    });

    test('dart fix', () async {
      testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
      final request = CallToolRequest(
        name: dartFixTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: exampleDartNativeAppRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: [endsWith(dartExecutableName), 'fix', '--apply'],
          workingDirectory: exampleDartNativeAppRoot.path,
        )),
      ]);
    });

    test('dart format', () async {
      testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          ParameterNames.roots: [
            {ParameterNames.root: exampleDartNativeAppRoot.uri},
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: [endsWith(dartExecutableName), 'format', '.'],
          workingDirectory: exampleDartNativeAppRoot.path,
        )),
      ]);
    });

    test('dart format with paths', () async {
      testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
      final request = CallToolRequest(
        name: dartFormatTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleDartNativeAppRoot.uri,
              ParameterNames.paths: ['foo.dart', 'bar.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: [
            endsWith(dartExecutableName),
            'format',
            'foo.dart',
            'bar.dart',
          ],
          workingDirectory: exampleDartNativeAppRoot.path,
        )),
      ]);
    });

    test('dartnative and dart package tests with paths', () async {
      testHarness.mcpClient.addRoot(dartCliAppRoot);
      testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
      await pumpEventQueue();
      final request = CallToolRequest(
        name: DashCliSupport.runTestsTool.name,
        arguments: {
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleDartNativeAppRoot.uri,
              ParameterNames.paths: ['foo_test.dart', 'bar_test.dart'],
            },
            {
              ParameterNames.root: dartCliAppRoot.uri,
              ParameterNames.paths: ['zip_test.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: [
            endsWith(dnExecutableName),
            'test',
            '--reporter=failures-only',
            'foo_test.dart',
            'bar_test.dart',
          ],
          workingDirectory: exampleDartNativeAppRoot.path,
        )),
        equalsCommand((
          command: [
            endsWith(dartExecutableName),
            'test',
            '--reporter=failures-only',
            'zip_test.dart',
          ],
          workingDirectory: dartCliAppRoot.path,
        )),
      ]);
    });

    test('dartnative and dart package tests with extra arguments', () async {
      testHarness.mcpClient.addRoot(dartCliAppRoot);
      testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
      await pumpEventQueue();
      final request = CallToolRequest(
        name: DashCliSupport.runTestsTool.name,
        arguments: {
          ParameterNames.arguments: {
            'run-skipped': true,
            'platform': ['vm', 'chrome'],
            'reporter': 'json',
          },
          ParameterNames.roots: [
            {
              ParameterNames.root: exampleDartNativeAppRoot.uri,
              ParameterNames.paths: ['foo_test.dart', 'bar_test.dart'],
            },
            {
              ParameterNames.root: dartCliAppRoot.uri,
              ParameterNames.paths: ['zip_test.dart'],
            },
          ],
        },
      );
      final result = await testHarness.callToolWithRetry(request);

      // Verify the command was sent to the process manager without error.
      expect(result.isError, isNot(true));
      expect(testProcessManager.commandsRan, [
        equalsCommand((
          command: [
            endsWith(dnExecutableName),
            'test',
            '--run-skipped',
            '--platform',
            'vm',
            '--platform',
            'chrome',
            '--reporter',
            'json',
            'foo_test.dart',
            'bar_test.dart',
          ],
          workingDirectory: exampleDartNativeAppRoot.path,
        )),
        equalsCommand((
          command: [
            endsWith(dartExecutableName),
            'test',
            '--run-skipped',
            '--platform',
            'vm',
            '--platform',
            'chrome',
            '--reporter',
            'json',
            'zip_test.dart',
          ],
          workingDirectory: dartCliAppRoot.path,
        )),
      ]);
    });

    group('create', () {
      test('creates a Dart project', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dart',
            ParameterNames.template: 'cli',
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(dartExecutableName),
              'create',
              '--template',
              'cli',
              'new_app',
            ],
            workingDirectory: dartCliAppRoot.path,
          )),
        ]);
      });

      test('creates a DartNative project', () async {
        testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleDartNativeAppRoot.uri,
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dartnative',
            ParameterNames.template: 'app',
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(dnExecutableName),
              'create',
              '--template',
              'app',
              '--empty',
              'new_app',
            ],
            workingDirectory: exampleDartNativeAppRoot.path,
          )),
        ]);
      });

      test('creates a non-empty DartNative project', () async {
        testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleDartNativeAppRoot.uri,
            ParameterNames.directory: 'new_full_app',
            ParameterNames.projectType: 'dartnative',
            ParameterNames.template: 'app',
            ParameterNames.empty:
                false, // Explicitly create a non-empty project
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(dnExecutableName),
              'create',
              '--template',
              'app',
              // Note: --empty is NOT present
              'new_full_app',
            ],
            workingDirectory: exampleDartNativeAppRoot.path,
          )),
        ]);
      });

      test('fails with invalid platform for DartNative project', () async {
        testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleDartNativeAppRoot.uri,
            ParameterNames.directory: 'my_app_invalid_platform',
            ParameterNames.projectType: 'dartnative',
            ParameterNames.platform: ['atari_jaguar', 'web'], // One invalid
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          allOf(
            contains('atari_jaguar is not a valid platform.'),
            contains(
              'Platforms `web`, `linux`, `macos`, `windows`, `android`, `ios` '
              'are the only allowed values',
            ),
          ),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails if projectType is missing', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'my_app_no_type',
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('Required property "projectType" is missing'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails with invalid projectType', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'my_app_invalid_type',
            ParameterNames.projectType: 'java', // Invalid type
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains(
            'Only `dart` and `dartnative` are allowed values.',
          ),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('creates a DartNative project in the root itself', () async {
        testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
        for (final directory in ['.', './']) {
          testProcessManager.commandsRan.clear();
          final request = CallToolRequest(
            name: createProjectTool.name,
            arguments: {
              ParameterNames.root: exampleDartNativeAppRoot.uri,
              ParameterNames.directory: directory,
              ParameterNames.projectType: 'dartnative',
            },
          );
          await testHarness.callToolWithRetry(request);

          expect(testProcessManager.commandsRan, [
            equalsCommand((
              command: [
                endsWith(dnExecutableName),
                'create',
                '--empty',
                directory,
              ],
              workingDirectory: exampleDartNativeAppRoot.path,
            )),
          ]);
        }
      });

      test('passes the root itself to dart create', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: './',
            ParameterNames.projectType: 'dart',
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [endsWith(dartExecutableName), 'create', './'],
            workingDirectory: dartCliAppRoot.path,
          )),
        ]);
      });

      test('fails if directory is empty', () async {
        testHarness.mcpClient.addRoot(exampleDartNativeAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: exampleDartNativeAppRoot.uri,
            ParameterNames.directory: '',
            ParameterNames.projectType: 'dartnative',
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('must not be empty'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails if directory (project name) is an absolute path', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: '/an/absolute/path/project',
            ParameterNames.projectType: 'dart',
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('Directory must be a relative path'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails if directory escapes root', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: '../outside',
            ParameterNames.projectType: 'dart',
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('within the project root'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('accepts a template with a literal backslash', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dart',
            ParameterNames.template: r'console\nfull',
          },
        );
        await testHarness.callToolWithRetry(request);

        expect(testProcessManager.commandsRan, [
          equalsCommand((
            command: [
              endsWith(dartExecutableName),
              'create',
              '--template',
              r'console\nfull',
              'new_app',
            ],
            workingDirectory: dartCliAppRoot.path,
          )),
        ]);
      });

      test('fails if template starts with a dash', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.root: dartCliAppRoot.uri,
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dart',
            ParameterNames.template: '--force',
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, isTrue);
        expect(
          (result.content.first as TextContent).text,
          contains('must not start with'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });

      test('fails if template contains whitespace', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        for (final template in [
          'console\nfull',
          'console\tfull',
          'console\rfull',
        ]) {
          final request = CallToolRequest(
            name: createProjectTool.name,
            arguments: {
              ParameterNames.root: dartCliAppRoot.uri,
              ParameterNames.directory: 'new_app',
              ParameterNames.projectType: 'dart',
              ParameterNames.template: template,
            },
          );
          final result = await testHarness.callTool(request, expectError: true);

          expect(result.isError, isTrue);
          expect(
            (result.content.first as TextContent).text,
            contains('contain whitespace'),
          );
          expect(testProcessManager.commandsRan, isEmpty);
        }
      });

      test('requires a root to be passed', () async {
        testHarness.mcpClient.addRoot(dartCliAppRoot);
        final request = CallToolRequest(
          name: createProjectTool.name,
          arguments: {
            ParameterNames.directory: 'new_app',
            ParameterNames.projectType: 'dart',
            ParameterNames.template: 'cli',
          },
        );
        final result = await testHarness.callTool(request, expectError: true);

        expect(result.isError, true);
        expect(
          (result.content.first as TextContent).text,
          contains('Required property "root" is missing'),
        );
        expect(testProcessManager.commandsRan, isEmpty);
      });
    });
  });
}
