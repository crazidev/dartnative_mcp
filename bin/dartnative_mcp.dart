// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dartnative_mcp/dartnative_mcp.dart';
import 'package:dartnative_mcp/src/install.dart';
import 'package:unified_analytics/unified_analytics.dart';

void main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'install') {
    exitCode = await runInstall(args.sublist(1));
    return;
  }

  DashTool? tool;
  if (Platform.environment[DashEnvVar.tool.name] case final toolEnv?) {
    try {
      tool = DashTool.fromLabel(toolEnv);
    } catch (e) {
      // Ignore errors, but don't track analytics for unrecognized tools.
    }
  }

  final analytics = tool != null
      ? Analytics(
          tool: tool,
          dartVersion: parseDartSDKVersion(Platform.version),
        )
      : null;

  try {
    exitCode = await DartNativeMCPServer.run(args, analytics: analytics);
  } finally {
    await analytics?.close();
  }
}
