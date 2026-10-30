# DartNative MCP Server

An [MCP](https://modelcontextprotocol.io) server for DartNative projects. It
exposes the DartNative (`dn`) CLI, the Dart analyzer, and the Dart Tooling
Daemon (DTD) to AI agents in VS Code, Cursor, OpenCode, Claude Code, and any
other MCP client that supports stdio.

This package is an independent extraction of the upstream
[`dart_mcp_server`](https://pub.dev/packages/dart_mcp_server) with the CLI
layer rewritten for DartNative:

- DartNative projects are detected from their `pubspec.yaml` (`dartnative` and
  `dartnative_*` dependencies).
- CLI tools (`pub`, `test`, `analyze`, `build`, `run`, `clean`, `devices`,
  `doctor`, `install`, `create`) run through `dn`.
- `dart format` and `dart fix` keep using the Dart SDK, because `dn` does not
  provide those commands.
- Analysis tools (`analyze_files`, `hover`, `resolve_workspace_symbol`, …) keep
  using the analysis server, which resolves DartNative packages correctly.

Only the `dn` and `dart` CLIs are supported.

## Status

Experimental (`0.x`). Tool schemas may change.

## Requirements

- A DartNative SDK (the SDK that ships `bin/dn`), for example
  `/path/to/dartnative` with `bin/dn` and `bin/dart`.
- An MCP client that supports stdio and, ideally,
  [Roots](https://modelcontextprotocol.io/docs/concepts/roots).

## Install

The DartNative VS Code extension installs the server for you with
**DartNative: Install MCP Server**. It fetches the latest version from GitHub,
activates it globally with `dart pub global activate`, and writes a
`.dartnative/mcp.bin` launcher plus the MCP client configuration.

To do the same manually:

```sh
dart pub global activate --source git https://github.com/crazidev/dartnative_mcp
```

Then point your MCP client at the launcher created by the extension:

```sh
<project>/.dartnative/mcp.bin
```

The launcher runs the globally activated package and passes the SDK paths:

```sh
dart pub global run dartnative_mcp --dn-sdk <dartnative-sdk> --enable cli
```

Useful flags:

```text
--dart-sdk <path>    Path to the Dart SDK root
--dn-sdk <path>      Path to the DartNative SDK root (ships bin/dn)
--log-file <path>    Log all MCP protocol traffic to a file
--enable <name>      Enable a tool or category
--disable <name>     Disable a tool or category
```

## Client configuration

All clients use the same stdio command: the project-local
`.dartnative/mcp.bin` launcher. Replace the path with your own.

### OpenCode (`opencode.json`)

```json
{
  "mcp": {
    "dartnative": {
      "type": "local",
      "command": ["/path/to/project/.dartnative/mcp.bin"],
      "enabled": true
    }
  }
}
```

### VS Code (`.vscode/mcp.json`)

```json
{
  "servers": {
    "dartnative": {
      "type": "stdio",
      "command": "/path/to/project/.dartnative/mcp.bin"
    }
  }
}
```

### Cursor (`.cursor/mcp.json`) and Claude Code (`.mcp.json`)

```json
{
  "mcpServers": {
    "dartnative": {
      "command": "/path/to/project/.dartnative/mcp.bin"
    }
  }
}
```

### Gemini CLI (`.gemini/settings.json`)

```json
{
  "mcpServers": {
    "dartnative": {
      "command": "/path/to/project/.dartnative/mcp.bin"
    }
  }
}
```

## Run from source

```sh
dart pub get
dart run bin/dartnative_mcp.dart
```

The server finds the SDKs automatically:

| SDK | Resolution order |
| --- | --- |
| Dart | `--dart-sdk`, `DART_ROOT`, `DART_SDK`, the running executable |
| DartNative | `--dn-sdk`, `DN_ROOT`, `DARTNATIVE_ROOT`, `bin/dn` next to the Dart SDK |

## Tools

### DartNative CLI

| Tool | Command |
| --- | --- |
| `dn_analyze` | `dn analyze` |
| `dn_build` | `dn build <target>` |
| `dn_clean` | `dn clean` |
| `dn_devices` | `dn devices` |
| `dn_doctor` | `dn doctor` |
| `dn_install` | `dn install` |
| `dn_run` | `dn run -d <device>` |
| `dn_stop_app` | stops a process started by `dn_run` |
| `dn_app_logs` | returns the logs of a process started by `dn_run` |

### Shared CLI

| Tool | Command |
| --- | --- |
| `pub` | `dn pub` or `dart pub` |
| `run_tests` | `dn test` or `dart test` |
| `create_project` | `dn create` or `dart create` |
| `dart_format` | `dart format` |
| `dart_fix` | `dart fix --apply` |

### Analyzer and runtime

`analyze_files`, `lsp`, `hover`, `resolve_workspace_symbol`,
`signature_help`, `read_package_uris`, `rip_grep_packages`, `pub_dev_search`,
the `dtd` tool, `hot_reload`, `hot_restart`, `get_runtime_errors`,
`get_active_location`, and `vm_service` are inherited from the upstream
server.

## Skills

The `skills/dartnative-mcp/SKILL.md` file is an agent skill that teaches an
assistant how to use the `dn_*` tools. The DartNative VS Code extension copies
it into a project when you run **DartNative: Install MCP Server**.

## Development

```sh
dart pub get
dart analyze
dart test
```

## License

BSD-3-Clause. See [LICENSE](LICENSE). This package is derived from
`dart_mcp_server`, copyright the Dart project authors.
