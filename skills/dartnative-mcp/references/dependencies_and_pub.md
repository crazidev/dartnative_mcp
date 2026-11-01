# Dependency Management (`pub`)

This guide covers package resolution, dependency management, and dependency inspection for DartNative projects. For **finding** packages, see [`pub_search.md`](./pub_search.md).

---

## 1. Overview

DartNative projects manage dependencies through `dn pub` commands via the `pub` MCP tool. Do not run `flutter pub` or manual terminal commands.

---

## 2. The `pub` Tool

### Supported commands

| Command | Purpose | Requires `packageNames` |
| :--- | :--- | :--- |
| `get` | Resolve and install dependencies listed in `pubspec.yaml`. | No |
| `add` | Add one or more package dependencies. | Yes |
| `remove` | Remove one or more package dependencies. | Yes |
| `upgrade` | Upgrade dependencies to their latest compatible versions. | No |
| `deps` | Print the dependency tree. | No |
| `outdated` | Report dependencies with newer available versions. | No |

### Parameters

- `command` (**required**): one of `get`, `add`, `remove`, `upgrade`, `deps`, `outdated`.
- `packageNames` (optional): list of package descriptors, used with `add` and `remove`.
- `roots` (optional): list of workspace roots (`file:` URIs) to run pub in. Omit to use the client-provided workspace roots.

> The parameter is `packageNames`, not `packages`. Using the wrong key fails schema validation.

### `packageNames` descriptors

`add` forwards each entry to pub, so the full descriptor syntax works:

- `"pkg_name"` — a normal dependency
- `"dev:pkg_name"` — a dev dependency
- `"override:pkg_name:1.0.0"` — a dependency override
- `"pkg_name:{git:{url: https://github.com/o/r.git, ref: main, path: subdir}}"` — git dependency
- `"pkg_name:{path: ../pkg_name}"` — path dependency

Entries starting with `-` are rejected so they cannot be interpreted as CLI flags.

---

## 3. Common Workflows

### Resolving missing dependencies

When `analyze_files` reports `uri_does_not_exist`:

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": { "command": "get" }
}
```

### Adding a dependency

Find the package first with `dartpub_search` (DartNative plugins) or `pub_dev_search` (pub.dev packages), then:

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": {
    "command": "add",
    "packageNames": ["path"]
  }
}
```

### Adding a dev dependency

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": {
    "command": "add",
    "packageNames": ["dev:test"]
  }
}
```

### Removing a dependency

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": {
    "command": "remove",
    "packageNames": ["path"]
  }
}
```

### Auditing dependencies

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": { "command": "outdated" }
}
```

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": { "command": "deps" }
}
```

### Inspecting an installed dependency

Search tools only describe packages. To read or grep their source, use `read_package_uris` and `rip_grep_packages` — see [`code_intelligence.md`](./code_intelligence.md).

---

## 4. After Any Dependency Change

1. Run `analyze_files` to confirm imports resolve.
2. If resolution errors remain, run `pub` with `command: "get"`.
3. Run `dart_format` before finishing the task.
