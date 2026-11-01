// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dartnative_mcp/src/mixins/dartpub_search.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';

import '../test_harness.dart';

/// Runs [fn] with the MCP server wired to [responses].
///
/// Keys are full request URLs; any request without a mapping fails with a
/// [ClientException], which mirrors being offline.
Future<void> runWithHarness(
  Future<void> Function(TestHarness harness, Tool tool) fn,
  Map<String, Response> responses,
) async {
  await runWithClient(() async {
    final testHarness = await TestHarness.start(inProcess: true);
    final tools = (await testHarness.mcpServerConnection.listTools()).tools;
    final tool = tools.singleWhere(
      (t) => t.name == DartpubSupport.dartpubSearchTool.name,
    );
    await fn(testHarness, tool);
  }, () => _FixedResponseClient(responses));
}

class _FixedResponseClient extends BaseClient {
  final Map<String, Response> responses;

  _FixedResponseClient(this.responses);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final response = responses[request.url.toString()];
    if (response == null) {
      throw ClientException('No internet', request.url);
    }
    return StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

Response _json(Object? body, {int statusCode = 200}) => Response(
  jsonEncode(body),
  statusCode,
  headers: {'content-type': 'application/json'},
);

const _searchUrl = 'https://dartpub.dev/api/plugins?q=camera&limit=10&page=1';

Map<String, Object?> _plugin(String name) => {
  'name': name,
  'tagline': 'Native camera for DartNative',
  'description': 'A hardware-backed camera preview widget for DartNative.',
  'license': {'label': 'MIT'},
  'runtime_min': 'DartNative \u2265 3.0',
  'source': 'sdk',
  'publisher': {'handle': 'DartNative', 'name': 'DartNative Team'},
  'repo': {'url': 'https://github.com/DartNative/dartnative'},
  'stats': {'weekly_installs': 12, 'active_apps': 3, 'upvotes': 4},
  'latest': {'version': '1.0.2'},
  'links': {'page': 'https://dartpub.dev/plugins/$name'},
};

void main() {
  test('searches the catalog and renders a compact summary', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(name: tool.name, arguments: {'query': 'camera'}),
        );

        expect(result.isError, isNot(true));
        expect(result.content, hasLength(1));
        final text = (result.content.single as TextContent).text;

        expect(
          text,
          contains('Found 2 DartNative plugin(s) for query "camera"'),
        );
        expect(text, contains('`dartnative_camera` — v1.0.2'));
        expect(text, contains('License: MIT'));
        expect(text, contains('Source: bundled with the SDK'));
        expect(text, contains('Publisher: DartNative Team (@DartNative)'));
        expect(text, contains('12 weekly installs'));
        expect(text, contains('packageNames: [...]'));
        // The raw registry payload must not be included by default.
        expect(text, isNot(contains('Raw API response')));
      },
      {
        _searchUrl: _json({
          'count': 2,
          'page': 1,
          'limit': 10,
          'plugins': [_plugin('dartnative_camera'), _plugin('mobile_scanner')],
        }),
      },
    );
  });

  test('includes the raw payload only when requested', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(
            name: tool.name,
            arguments: {'query': 'camera', 'raw': true},
          ),
        );

        final text = (result.content.single as TextContent).text;
        expect(text, contains('Raw API response'));
        expect(text, contains('"name": "dartnative_camera"'));
      },
      {
        _searchUrl: _json({
          'count': 1,
          'plugins': [_plugin('dartnative_camera')],
        }),
      },
    );
  });

  test('explains an empty result set', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(name: tool.name, arguments: {'query': 'camera'}),
        );

        expect(result.isError, isNot(true));
        final text = (result.content.single as TextContent).text;
        expect(text, contains('No DartNative plugins matched'));
        expect(text, contains('pub_dev_search'));
      },
      {
        _searchUrl: _json({'count': 0, 'plugins': <Object?>[]}),
      },
    );
  });

  test('distinguishes an out-of-range page from no matches', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(
            name: tool.name,
            arguments: {'query': 'camera', 'page': 2},
          ),
        );

        final text = (result.content.single as TextContent).text;
        expect(text, contains('No plugins on page 2'));
        expect(text, contains('try a lower `page`'));
      },
      {
        'https://dartpub.dev/api/plugins?q=camera&limit=10&page=2': _json({
          'count': 2,
          'plugins': <Object?>[],
        }),
      },
    );
  });

  test('fetches plugin details by name', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(
            name: tool.name,
            arguments: {'name': 'dartnative_camera'},
          ),
        );

        final text = (result.content.single as TextContent).text;
        expect(text, startsWith('# dartnative_camera'));
        expect(text, contains('- **Version**: 1.0.2'));
        expect(
          text,
          contains('- **Publisher**: DartNative Team (@DartNative)'),
        );
        expect(text, contains('## Install'));
        expect(text, contains('dn pub add dartnative_camera'));
      },
      {
        'https://dartpub.dev/api/plugins/dartnative_camera': _json(
          _plugin('dartnative_camera'),
        ),
      },
    );
  });

  test('fetches a README as markdown', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(
            name: tool.name,
            arguments: {'name': 'dartnative_camera', 'detail': 'readme'},
          ),
        );

        expect(result.isError, isNot(true));
        final text = (result.content.single as TextContent).text;
        expect(text, startsWith('# Readme for `dartnative_camera`'));
        expect(text, contains('# dartnative_camera'));
        expect(text, contains('Snap points'));
      },
      {
        'https://dartpub.dev/api/plugins/dartnative_camera/readme': Response(
          '# dartnative_camera\n\nSnap points\n',
          200,
          headers: {'content-type': 'text/markdown'},
        ),
      },
    );
  });

  test('reports a missing plugin with an actionable message', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(
            name: tool.name,
            arguments: {'name': 'does_not_exist'},
          ),
        );

        expect(result.isError, isTrue);
        final text = (result.content.single as TextContent).text;
        expect(text, contains('was not found on dartpub.dev'));
        expect(text, contains('with a `query` to find the right plugin name'));
      },
      {
        'https://dartpub.dev/api/plugins/does_not_exist': _json({
          'error': 'not_found',
        }, statusCode: 404),
      },
    );
  });

  test('surfaces registry errors from the API body', () async {
    await runWithHarness(
      (harness, tool) async {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(name: tool.name, arguments: {'query': 'camera'}),
        );

        expect(result.isError, isTrue);
        final text = (result.content.single as TextContent).text;
        expect(text, contains('HTTP 500'));
        expect(text, contains('registry is having a bad day'));
      },
      {
        _searchUrl: _json({
          'error': 'internal',
          'message': 'registry is having a bad day',
        }, statusCode: 500),
      },
    );
  });

  test('rejects conflicting and incomplete arguments', () async {
    await runWithHarness((harness, tool) async {
      final both = await harness.mcpServerConnection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {'name': 'a', 'query': 'b'},
        ),
      );
      expect(both.isError, isTrue);
      expect((both.content.single as TextContent).text, contains('not both'));

      final detailOnly = await harness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name, arguments: {'detail': 'readme'}),
      );
      expect(detailOnly.isError, isTrue);
      expect(
        (detailOnly.content.single as TextContent).text,
        contains('requires `name`'),
      );
    }, const {});
  });

  test('schema rejects out-of-range paging values', () async {
    await runWithHarness((harness, tool) async {
      for (final arguments in <Map<String, Object?>>[
        {'limit': 0},
        {'limit': 101},
        {'page': 0},
      ]) {
        final result = await harness.mcpServerConnection.callTool(
          CallToolRequest(name: tool.name, arguments: arguments),
        );
        expect(result.isError, isTrue, reason: '$arguments should be rejected');
        expect(
          result.content.map((c) => (c as TextContent).text).join(),
          contains('Invalid tool arguments'),
        );
      }
    }, const {});
  });

  test('reports a transport failure as an error', () async {
    await runWithHarness((harness, tool) async {
      final result = await harness.mcpServerConnection.callTool(
        CallToolRequest(name: tool.name, arguments: {'query': 'camera'}),
      );

      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('Failed communicating with the dartpub.dev API'),
      );
    }, const {});
  });
}
