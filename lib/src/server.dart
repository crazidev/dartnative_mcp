// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:unified_analytics/unified_analytics.dart';

import 'arg_parser.dart';
import 'features_configuration.dart';
import 'mixins/analytics.dart';
import 'mixins/analyzer.dart';
import 'mixins/dartnative.dart';
import 'mixins/dash_cli.dart';
import 'mixins/dtd.dart';
import 'mixins/grep_packages.dart';
import 'mixins/package_uri_reader.dart';
import 'mixins/dartpub_search.dart';
import 'mixins/pub.dart';
import 'mixins/pub_dev_search.dart';
import 'mixins/roots_fallback_support.dart';
import 'utils/analytics.dart';
import 'utils/file_system.dart';
import 'utils/names.dart';
import 'utils/process_manager.dart';
import 'utils/sdk.dart';

/// An MCP server for Dart and DartNative tooling.
final class DartNativeMCPServer extends MCPServer
    with
        LoggingSupport,
        ToolsSupport,
        ResourcesSupport,
        RootsTrackingSupport,
        RootsFallbackSupport,
        DashCliSupport,
        DartNativeCliSupport,
        DartAnalyzerSupport,
        PubSupport,
        PubDevSupport,
        DartpubSupport,
        DartToolingDaemonSupport,
        PromptsSupport,
        PackageUriSupport,
        ElicitationRequestSupport,
        GrepSupport,
        AnalyticsEvents
    implements
        AnalyticsSupport,
        ProcessManagerSupport,
        FileSystemSupport,
        SdkSupport {
  /// Controls which features are enabled for this run.
  final FeaturesConfiguration featuresConfig;

  /// The default arg parser for the MCP Server.
  static final argParser = createArgParser();

  @override
  final ProcessManager processManager;

  @override
  final FileSystem fileSystem;

  @override
  final Sdk sdk;

  @override
  final Analytics? analytics;

  DartNativeMCPServer(
    super.channel, {
    required this.sdk,
    required this.featuresConfig,
    this.analytics,
    @visibleForTesting this.processManager = const LocalProcessManager(),
    @visibleForTesting this.fileSystem = const LocalFileSystem(),
    super.protocolLogSink,
  }) : super.fromStreamChannel(
         implementation: Implementation(
           name: 'dartnative tooling',
           description:
               'Connects DartNative apps and developer tools to AI agents.',
           version: version,
         ),
         instructions:
             '''
Prefer the `dn_*` tools over running shell commands: they use the DartNative
`dn` CLI and return agent-friendly output. Use `${ToolNames.dnDevices.name}` to
discover devices, `${ToolNames.dnRun.name}` to launch an app, and
`${ToolNames.dnBuild.name}` to build one.

Always run `${ToolNames.analyzeFiles.name}` first before starting any work to
discover errors, warnings, or missing dependencies. If dependencies are missing,
run `${ToolNames.pub.name}` with command `get`.

After completing code changes or any job, always run
`${ToolNames.analyzeFiles.name}` to verify there are no remaining errors or
warnings, and format code with `${ToolNames.dartFormat.name}`.

If there are no blocker errors but there are simple lints to be fixed, use
`${ToolNames.dartFix.name}` (or `${ToolNames.analyzeFiles.name}` with `applyFixes: true`)
to fix them automatically instead of editing each file manually.

After completing Dart/DartNative code changes, always execute a hot reload or
hot restart.

Tools that interact with a running app require a connection to the Dart
Tooling Daemon (DTD) first. If you are not connected yet, proactively connect
using the `${DartToolingDaemonSupport.dtdTool.name}` tool: first call it with
command `${DtdCommand.listDtdUris}` to find DTD URIs, then call it with
command `${DtdCommand.connect}` and the chosen `uri`. Only after connecting
will `${DtdCommand.listConnectedApps}` return any apps.

Whenever attempting to investigate a package dependency, use the
`${ToolNames.readPackageUris}` and `${ToolNames.ripGrepPackages}` tools to
explore their files.

To find DartNative plugins (camera, bottom sheets, app links, …), use
`${ToolNames.dartpubSearch.name}` to query the dartpub.dev plugin registry.
It can also return a plugin's README, example, or changelog via `detail`.
For ordinary Dart packages, use `${ToolNames.pubDevSearch.name}` to search
pub.dev instead.
Install discovered dependencies using `${ToolNames.pub.name}` with command `add`.

In addition to `package:` URIs, the server also supports `package-root:` URIs,
which resolve to the root of the package instead of the `lib/` directory. These
can be useful for exporing examples or tests when trying to learn how to use a
package.
''',
       );

  /// The version of the MCP server.
  ///
  /// Should match the version in `pubspec.yaml` and `CHANGELOG.md`.
  static final version = '0.1.0';

  /// Runs the MCP server given command line arguments and an optional
  /// [Analytics] instance.
  ///
  /// If [channel] is provided, then it will be used for communication,
  /// otherwise a stdio channel will be used.
  ///
  /// Returns a [Future] that completes with an exit code after the server has
  /// shut down.
  static Future<int> run(
    List<String> args, {
    Analytics? analytics,
    StreamChannel<String>? channel,
  }) async {
    final parsedArgs = argParser.parse(args);
    if (parsedArgs.flag(helpFlag)) {
      print(argParser.usage);
      return 0;
    }

    if (parsedArgs.flag(versionFlag)) {
      print(version);
      return 0;
    }

    DartNativeMCPServer? server;
    final logFilePath = parsedArgs.option(logFileOption);
    final logFileSink = logFilePath == null
        ? null
        : _createLogSink(io.File(logFilePath));
    runZonedGuarded(
      () {
        server = DartNativeMCPServer(
          channel ?? stdioChannel(input: io.stdin, output: io.stdout),
          featuresConfig: FeaturesConfiguration.fromArgs(parsedArgs),
          sdk: Sdk.find(
            dartSdkPath: parsedArgs.option(dartSdkOption),
            dnSdkPath: parsedArgs.option(dnSdkOption),
          ),
          analytics: analytics,
          protocolLogSink: logFileSink,
        )..done.whenComplete(() => logFileSink?.close());
      },
      (e, s) {
        if (server != null) {
          try {
            // Log unhandled errors to the client, if we managed to connect.
            server!.log(LoggingLevel.error, '$e\n$s');
          } catch (_) {}
        } else {
          // Otherwise log to stderr.
          io.stderr
            ..writeln(e)
            ..writeln(s);
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, value) {
          if (server != null) {
            try {
              // Don't allow `print` since this breaks stdio communication, but
              // if we have a server we do log messages to the client.
              server!.log(LoggingLevel.info, value);
            } catch (_) {}
          }
        },
      ),
    );
    if (server == null) {
      return 1;
    } else {
      await server!.done;
      return 0;
    }
  }

  @override
  /// Only actually registers the tools enabled by [featuresConfig].
  void registerTool(
    Tool tool,
    FutureOr<CallToolResult> Function(CallToolRequest) impl, {
    bool validateArguments = true,
  }) {
    if (!featuresConfig.isEnabled(
      tool.name,
      tool.enabledByDefault,
      tool.categories,
    )) {
      return;
    }
    super.registerTool(tool, impl, validateArguments: validateArguments);
  }
}

/// Creates a `Sink<String>` for [logFile].
Sink<String> _createLogSink(io.File logFile) {
  logFile.createSync(recursive: true);
  final fileByteSink = logFile.openWrite(
    mode: io.FileMode.write,
    encoding: utf8,
  );
  return fileByteSink.transform(
    StreamSinkTransformer.fromHandlers(
      handleData: (data, innerSink) {
        innerSink.add(utf8.encode(data));
      },
      handleDone: (innerSink) async {
        innerSink.close();
      },
      handleError: (Object e, StackTrace s, _) {
        io.stderr.writeln(
          'Error in writing to log file ${logFile.path}: $e\n$s',
        );
      },
    ),
  );
}
