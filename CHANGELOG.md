## 0.1.0

Initial independent extraction of
[`dart_mcp_server`](https://pub.dev/packages/dart_mcp_server) 1.2.2 for
DartNative.

- Package renamed from `dart_mcp_server` to `dartnative_mcp`; server
  implementation renamed to `DartNativeMCPServer`.
- Added `Sdk.dnSdkPath` / `Sdk.dnExecutablePath`, the `--dn-sdk` option, and the
  `DN_ROOT` / `DARTNATIVE_ROOT` environment variables.
- Added `ProjectKind.dartnative`, detected from `dartnative` /
  `dartnative_*` dependencies in `pubspec.yaml`.
- CLI tools (`pub`, `run_tests`, `create_project`) now use `dn` for DartNative
  projects.
- Added `dn_analyze`, `dn_build`, `dn_clean`, `dn_devices`, `dn_doctor`,
  `dn_install`, `dn_run`, `dn_stop_app`, and `dn_app_logs` tools.
- Added the `dartnative` feature category.
- Relaxed the SDK constraint to `^3.12.0-0` so DartNative's pre-release Dart
  SDKs resolve.
- Added `skills/dartnative-mcp/SKILL.md` for agent integrations, with modular
  reference guides under `skills/dartnative-mcp/references/`.
- Added the `dartpub_search` tool for the DartNative plugin registry on
  dartpub.dev, including plugin metadata, README, example, and changelog
  retrieval, owner/status/sort filters, and paging.
- Removed Flutter-specific tooling: `launch_app`, `stop_app`,
  `list_running_apps`, `get_app_logs`, `list_devices`, `flutter_driver_command`,
  the Flutter driver prompt, `ProjectKind.flutter`, and the `--flutter-sdk`
  option. Only `dn` and `dart` are supported.
- Removed the Flutter-only `widget_inspector` tool (`get_widget_tree`,
  `get_selected_widget`, and `set_widget_selection_mode`), which relies on
  Flutter inspector service extensions that are not available in DartNative.
