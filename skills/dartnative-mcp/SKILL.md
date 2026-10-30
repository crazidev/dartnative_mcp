---
name: dartnative-mcp
description: Use the DartNative MCP server to run, build, test, and analyze DartNative projects with the dn CLI. Use when a project depends on dartnative or dartnative_* packages, when you need to launch an app on a device, read its logs, or run dn build/dn test/dn pub.
---

# DartNative MCP

The `dartnative` MCP server exposes the DartNative `dn` CLI, the Dart analyzer,
and the Dart Tooling Daemon to your agent. Prefer these tools over shelling out
to `dn` or `dart`.

## Rule: only `dn` and `dart`

DartNative projects are built with `dn`; analysis and formatting use `dart`.
Do not invoke any other SDK CLI. Use the matching MCP tool instead of running
shell commands whenever one exists.

## Tools

### Project commands

| Tool | Use it for |
| --- | --- |
| `pub` | `dn pub get`, `add`, `remove`, `upgrade`, `deps`, `outdated` |
| `run_tests` | `dn test` with `package:test` arguments |
| `dn_analyze` | `dn analyze` (raw CLI output) |
| `dn_build` | `dn build apk`, `appbundle`, `aar`, `ios`, `ipa`, `macos`, `linux`, `windows`, `web` |
| `dn_clean` | `dn clean` |
| `create_project` | `dn create` when `projectType` is `dartnative` |

### Devices and apps

| Tool | Use it for |
| --- | --- |
| `dn_devices` | list connected devices and emulators |
| `dn_run` | launch the app on a device; returns `pid`, `ready`, and startup logs |
| `dn_app_logs` | read the last N log lines for a `pid` returned by `dn_run` |
| `dn_stop_app` | stop an app started by `dn_run` |
| `dn_install` | install the app on a device |
| `dn_doctor` | diagnose the toolchain |

### Analysis

Use `analyze_files` for structured diagnostics, `lsp` for hover, symbols and
signature help, and `read_package_uris` / `rip_grep_packages` to inspect
dependency sources.

### Runtime

Connect to the Dart Tooling Daemon first with the `dtd` tool
(`listDtdUris`, then `connect`), then use `hot_reload`, `hot_restart`,
and `get_runtime_errors`.

## Typical workflow

1. `dn_devices` to pick a device ID.
2. `pub` with `get` after changing dependencies.
3. `run_tests` before building.
4. `dn_run` with the device ID; keep the returned `pid`.
5. `dn_app_logs` to check startup; `dn_stop_app` when done.
6. `dn_build` for a release artifact.

## Notes

- Tools that take `roots` accept the project root as a `file:` URI. Omit them
  to use the client-provided workspace roots.
- `dn_run` keeps the process alive. Always stop it with `dn_stop_app`, or the
  device stays occupied.
- `dart_format` and `dart_fix` use the Dart SDK because `dn` has no `format` or
  `fix` command.
