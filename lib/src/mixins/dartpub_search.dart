// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:dartnative_mcp/src/utils/analytics.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';

import '../features_configuration.dart';
import '../utils/names.dart';

/// The host serving the DartNative plugin registry.
const _host = 'dartpub.dev';

/// How long to wait for the registry before giving up.
const _requestTimeout = Duration(seconds: 30);

/// The maximum number of results the registry will return in one page.
const _maxLimit = 100;

/// The default number of results per page.
const _defaultLimit = 10;

/// Mix this in to [MCPServer] to add support for searching and inspecting
/// DartNative plugins on dartpub.dev.
///
/// This only covers the DartNative plugin registry (`/api/plugins`). Ordinary
/// Dart packages (for example `http` or `path`) must be searched on pub.dev
/// with the separate `pub_dev_search` tool.
base mixin DartpubSupport on ToolsSupport {
  final _client = Client();

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(dartpubSearchTool, _runDartpubSearch);
    return super.initialize(request);
  }

  @visibleForTesting
  static final List<Tool> allTools = [dartpubSearchTool];

  /// Implementation of the [dartpubSearchTool].
  Future<CallToolResult> _runDartpubSearch(CallToolRequest request) async {
    final args = request.arguments ?? const <String, Object?>{};
    final query = _asString(args['query'])?.trim();
    final name = _asString(args['name'])?.trim();
    final owner = _asString(args['owner'])?.trim();
    final sort = _asString(args['sort'])?.trim();
    final status = _asString(args['status'])?.trim();
    final detail = (_asString(args['detail']) ?? 'info').toLowerCase();
    final raw = args['raw'] == true;
    final limit = _asInt(args['limit']) ?? _defaultLimit;
    final page = _asInt(args['page']) ?? 1;

    // Validate locally so that the caller gets an actionable message instead
    // of a raw HTTP 400 from the registry.
    if (limit < 1 || limit > _maxLimit) {
      return _argumentError(
        '`limit` must be between 1 and $_maxLimit (got $limit).',
      );
    }
    if (page < 1) {
      return _argumentError('`page` must be 1 or greater (got $page).');
    }
    if (name != null && query != null) {
      return _argumentError(
        'Provide either `name` (inspect one plugin) or `query` (search the '
        'catalog), not both.',
      );
    }
    if (name == null && detail != 'info') {
      return _argumentError(
        '`detail: "$detail"` requires `name`, because it fetches content for a '
        'single plugin.',
      );
    }

    final headers = {
      'User-Agent': 'dartnative-mcp/0.1.0 (DartNative MCP Server)',
      'Accept':
          detail == 'readme' || detail == 'example' || detail == 'changelog'
          ? 'text/plain, text/markdown, application/json'
          : 'application/json',
    };

    try {
      if (name != null && name.isNotEmpty) {
        return await _describePlugin(
          name: name,
          detail: detail,
          headers: headers,
          includeRaw: raw,
        );
      }
      return await _searchPlugins(
        query: query,
        owner: owner,
        sort: sort,
        status: status,
        limit: limit,
        page: page,
        headers: headers,
        includeRaw: raw,
      );
    } on TimeoutException {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Timed out after ${_requestTimeout.inSeconds}s waiting for '
                '$_host. Try again in a moment.',
          ),
        ],
        isError: true,
      )..failureReason = CallToolFailureReason.timeout;
    } on Exception catch (e) {
      return CallToolResult(
          content: [
            TextContent(text: 'Failed communicating with the $_host API: $e'),
          ],
          isError: true,
        )
        ..failureReason = switch (e) {
          ClientException() => CallToolFailureReason.httpClientException,
          FormatException() => CallToolFailureReason.unhandledError,
          _ => CallToolFailureReason.unhandledError,
        };
    }
  }

  /// Fetches metadata (or a `readme`/`example`/`changelog`) for a single
  /// plugin.
  Future<CallToolResult> _describePlugin({
    required String name,
    required String detail,
    required Map<String, String> headers,
    required bool includeRaw,
  }) async {
    final path = switch (detail) {
      'readme' => 'api/plugins/$name/readme',
      'example' => 'api/plugins/$name/example',
      'changelog' => 'api/plugins/$name/changelog',
      _ => 'api/plugins/$name',
    };
    final response = await _get(path, headers: headers);

    if (response.statusCode == 404) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Plugin "$name" was not found on $_host (HTTP 404). '
                'Check the spelling, or run `${ToolNames.dartpubSearch.name}` '
                'with a `query` to find the right plugin name.',
          ),
        ],
        isError: true,
      )..failureReason = CallToolFailureReason.argumentError;
    }
    if (response.statusCode != 200) {
      return _httpError(
        response,
        'Failed retrieving $detail for plugin "$name"',
      );
    }

    if (detail != 'info') {
      final body = response.body.trim();
      if (body.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(text: 'Plugin "$name" has no $detail content.'),
          ],
        );
      }
      final title = detail[0].toUpperCase() + detail.substring(1);
      return CallToolResult(
        content: [TextContent(text: '# $title for `$name`\n\n$body')],
      );
    }

    final data = _asMap(jsonDecode(response.body));
    if (data == null) {
      return _unexpectedPayload('plugin "$name"');
    }

    final latest = _asMap(data['latest']);
    final publisher = _asMap(data['publisher']);
    final repo = _asMap(data['repo']);
    final license = _asMap(data['license']);
    final stats = _asMap(data['stats']);
    final links = _asMap(data['links']);

    final buffer = StringBuffer()
      ..writeln('# ${data['name'] ?? name}')
      ..writeln()
      ..writeln(_asString(data['tagline']) ?? '');
    final description = _asString(data['description']);
    if (description != null && description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }
    buffer
      ..writeln()
      ..writeln('## Details')
      ..writeln('- **Version**: ${_asString(latest?['version']) ?? 'unknown'}')
      ..writeln('- **Publisher**: ${_publisher(publisher)}')
      ..writeln('- **License**: ${_asString(license?['label']) ?? 'Unknown'}')
      ..writeln(
        '- **Runtime**: ${_asString(data['runtime_min']) ?? 'DartNative'}',
      )
      ..writeln('- **Status**: ${_asString(data['status']) ?? 'published'}')
      ..writeln('- **Repository**: ${_asString(repo?['url']) ?? 'unknown'}');

    final docsUrl = _asString(links?['page']);
    if (docsUrl != null) buffer.writeln('- **Docs**: $docsUrl');
    final exampleUrl = _asString(repo?['example_url']);
    if (exampleUrl != null) buffer.writeln('- **Example**: $exampleUrl');

    final statLine = _statsLine(stats);
    if (statLine != null) buffer.writeln('- **Stats**: $statLine');

    final versions = data['versions'];
    if (versions is List && versions.length > 1) {
      final recent = versions
          .whereType<Map>()
          .map((v) => _asString(v['version']))
          .whereType<String>()
          .take(5)
          .join(', ');
      if (recent.isNotEmpty) buffer.writeln('- **Recent versions**: $recent');
    }

    buffer
      ..writeln()
      ..writeln('## Install')
      ..writeln(
        'Call `${ToolNames.pub.name}` with '
        '`command: "add"` and `packageNames: ["$name"]`, or run:',
      )
      ..writeln('```sh')
      ..writeln('dn pub add $name')
      ..writeln('```');

    if (includeRaw) {
      buffer
        ..writeln()
        ..writeln('## Raw API response')
        ..writeln('```json')
        ..writeln(const JsonEncoder.withIndent('  ').convert(data))
        ..writeln('```');
    }

    return CallToolResult(content: [TextContent(text: buffer.toString())]);
  }

  /// Searches the plugin catalog.
  Future<CallToolResult> _searchPlugins({
    required String? query,
    required String? owner,
    required String? sort,
    required String? status,
    required int limit,
    required int page,
    required Map<String, String> headers,
    required bool includeRaw,
  }) async {
    final queryParams = <String, String>{
      if (query != null && query.isNotEmpty) 'q': query,
      if (owner != null && owner.isNotEmpty) 'owner': owner,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (status != null && status.isNotEmpty) 'status': status,
      'limit': '$limit',
      'page': '$page',
    };

    final response = await _get(
      'api/plugins',
      queryParameters: queryParams,
      headers: headers,
    );
    if (response.statusCode != 200) {
      return _httpError(response, 'Failed querying the $_host plugin catalog');
    }

    final result = _asMap(jsonDecode(response.body));
    if (result == null) return _unexpectedPayload('the plugin catalog');

    final plugins =
        (result['plugins'] as List?)
            ?.whereType<Map>()
            .map((p) => p.cast<String, Object?>())
            .toList() ??
        const <Map<String, Object?>>[];
    final total = _asInt(result['count']) ?? plugins.length;

    if (plugins.isEmpty) {
      if (page > 1) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'No plugins on page $page (limit $limit). There are '
                  '${total == 0 ? 'no' : total} matching plugins in total, so '
                  'try a lower `page`.',
            ),
          ],
        );
      }
      return CallToolResult(
        content: [
          TextContent(
            text:
                'No DartNative plugins matched on $_host. Try broader keywords, '
                'drop filters such as `owner`/`status`, or search pub.dev '
                'packages with `${ToolNames.pubDevSearch.name}` instead.',
          ),
        ],
      );
    }

    final filters = <String>[
      if (query != null && query.isNotEmpty) 'query "$query"',
      if (owner != null && owner.isNotEmpty) 'owner "$owner"',
      if (status != null && status.isNotEmpty) 'status "$status"',
    ];
    final first = (page - 1) * limit + 1;
    final last = first + plugins.length - 1;
    final buffer = StringBuffer()
      ..writeln(
        'Found $total DartNative plugin(s)'
        '${filters.isEmpty ? '' : ' for ${filters.join(', ')}'} '
        '(showing $first–$last, page $page, limit $limit).',
      )
      ..writeln();

    for (final plugin in plugins) {
      final pluginName = _asString(plugin['name']) ?? 'unknown';
      final latest = _asMap(plugin['latest']);
      final publisher = _asMap(plugin['publisher']);
      final repo = _asMap(plugin['repo']);
      final license = _asMap(plugin['license']);
      final stats = _asMap(plugin['stats']);
      final links = _asMap(plugin['links']);

      buffer
        ..writeln(
          '### `$pluginName` — v${_asString(latest?['version']) ?? 'unknown'}',
        )
        ..writeln(_asString(plugin['tagline']) ?? '');

      final description = _asString(plugin['description']);
      if (description != null && description.isNotEmpty) {
        buffer.writeln(_truncate(description, 280));
      }

      final meta = <String>[
        if (_asString(license?['label']) case final label?) 'License: $label',
        if (_asString(plugin['runtime_min']) case final runtime?)
          'Runtime: $runtime',
        if (_asString(plugin['source']) case final source?)
          'Source: ${source == 'sdk' ? 'bundled with the SDK' : 'published package'}',
        if (publisher != null) 'Publisher: ${_publisher(publisher)}',
      ];
      if (meta.isNotEmpty) buffer.writeln('- ${meta.join(' · ')}');

      final statLine = _statsLine(stats);
      if (statLine != null) buffer.writeln('- Stats: $statLine');

      final docs = _asString(links?['page']);
      final repoUrl = _asString(repo?['url']);
      final linksLine = [?docs, ?repoUrl];
      if (linksLine.isNotEmpty) {
        buffer.writeln('- Links: ${linksLine.join(' · ')}');
      }

      buffer.writeln();
    }

    buffer
      ..writeln('---')
      ..writeln(
        'Inspect one with `${ToolNames.dartpubSearch.name}` and '
        '`name: "<plugin>"` (add `detail: "readme"`, `"example"`, or '
        '`"changelog"` for docs). Install with `${ToolNames.pub.name}` '
        '`command: "add"` and `packageNames: [...]`.',
      );

    if (last < total) {
      buffer.writeln('Next page: `page: ${page + 1}`.');
    }

    if (includeRaw) {
      buffer
        ..writeln()
        ..writeln('## Raw API response')
        ..writeln('```json')
        ..writeln(const JsonEncoder.withIndent('  ').convert(result))
        ..writeln('```');
    }

    return CallToolResult(content: [TextContent(text: buffer.toString())]);
  }

  Future<Response> _get(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
  }) {
    final url = Uri.https(_host, path, queryParameters);
    return _client.get(url, headers: headers).timeout(_requestTimeout);
  }

  CallToolResult _httpError(Response response, String message) {
    final reason = _asMap(_tryDecode(response.body));
    final detail =
        _asString(reason?['message']) ??
        (response.body.trim().isEmpty ? null : _truncate(response.body, 500));
    return CallToolResult(
      content: [
        TextContent(
          text: ['$message: HTTP ${response.statusCode}', ?detail].join('\n'),
        ),
      ],
      isError: true,
    )..failureReason = CallToolFailureReason.httpClientException;
  }

  CallToolResult _argumentError(String message) => CallToolResult(
    content: [TextContent(text: 'Invalid arguments: $message')],
    isError: true,
  )..failureReason = CallToolFailureReason.argumentError;

  CallToolResult _unexpectedPayload(String what) => CallToolResult(
    content: [
      TextContent(
        text:
            'The $_host API returned an unexpected payload for $what. '
            'The registry response format may have changed.',
      ),
    ],
    isError: true,
  )..failureReason = CallToolFailureReason.unhandledError;

  static final dartpubSearchTool = Tool(
    name: ToolNames.dartpubSearch.name,
    description:
        'Searches the DartNative plugin registry on dartpub.dev, or fetches '
        'full metadata, README, example, or changelog for one plugin. '
        'Use this to find DartNative plugins (for example "camera", '
        '"bottomsheet", "app_links") and the exact `pub add` command to install '
        'them. It does NOT search general pub.dev packages; use '
        '`pub_dev_search` for those.',
    annotations: ToolAnnotations(
      title: 'DartNative plugin search',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          title: 'Search query',
          description:
              'Keywords to search the DartNative plugin catalog, for example '
              '"camera", "bottomsheet", or "app links". Omit to list plugins '
              '(combine with `sort`/`owner` to browse).',
        ),
        'name': Schema.string(
          title: 'Plugin name',
          description:
              'Exact plugin name to inspect, for example '
              '"native_bottomsheet". Use this instead of `query` when you '
              'already know the name.',
        ),
        'detail': Schema.string(
          title: 'Detail type',
          description:
              'Only valid together with `name`. Controls what is returned: '
              '"info" (default, structured metadata), "readme" (README '
              'markdown), "example" (example code), or "changelog".',
          // ignore: deprecated_member_use
          enumValues: ['info', 'readme', 'example', 'changelog'],
        ),
        'owner': Schema.string(
          title: 'GitHub owner / organization',
          description:
              'Only return plugins owned by this GitHub account, for example '
              '"DartNative" or "crazidev".',
        ),
        'sort': Schema.string(
          title: 'Sort order',
          description:
              'Sort catalog results by "name" (default), "installs", '
              '"active_apps", "upvotes", or "created".',
          // ignore: deprecated_member_use
          enumValues: ['name', 'installs', 'active_apps', 'upvotes', 'created'],
        ),
        'status': Schema.string(
          title: 'Plugin status',
          description:
              'Filter by status: "published" (default), "archived", or "all".',
          // ignore: deprecated_member_use
          enumValues: ['published', 'archived', 'all'],
        ),
        'limit': Schema.int(
          title: 'Results per page',
          description:
              'Number of results to return, from 1 to 100 (default 10).',
          minimum: 1,
          maximum: _maxLimit,
        ),
        'page': Schema.int(
          title: 'Page number',
          description: 'Page to return, starting at 1 (default 1).',
          minimum: 1,
        ),
        'raw': Schema.bool(
          title: 'Include raw response',
          description:
              'Append the raw JSON returned by the registry. Off by default '
              'because it is large and duplicates the summary.',
        ),
      },
      additionalProperties: false,
    ),
  )..categories = [FeatureCategory.dartnative, FeatureCategory.packageDeps];
}

/// Renders the `stats` object shared by search results and plugin details.
String? _statsLine(Map<String, Object?>? stats) {
  if (stats == null) return null;
  final parts = <String>[
    if (_asInt(stats['weekly_installs']) case final installs?)
      '$installs weekly installs',
    if (_asInt(stats['active_apps']) case final apps?) '$apps active apps',
    if (_asInt(stats['upvotes']) case final upvotes?) '$upvotes upvotes',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Formats a publisher object such as `{"name": "Jane", "handle": "jane"}`.
String _publisher(Map<String, Object?>? publisher) {
  final name = _asString(publisher?['name']);
  final handle = _asString(publisher?['handle']);
  if (name == null) return handle == null ? 'unknown' : '@$handle';
  return handle == null ? name : '$name (@$handle)';
}

String _truncate(String value, int max) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return singleLine.length <= max
      ? singleLine
      : '${singleLine.substring(0, max).trimRight()}…';
}

Map<String, Object?>? _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

String? _asString(Object? value) => value is String ? value : null;

int? _asInt(Object? value) => value is num ? value.toInt() : null;

Object? _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}
