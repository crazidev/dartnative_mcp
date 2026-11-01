# Code Intelligence & Source Navigation

This guide covers inspecting dependency source code, symbol navigation, and language server capabilities.

---

## 1. Overview

The `dartnative` MCP server provides Language Server Protocol (LSP) capabilities and tools to read or search resolved package dependencies without leaving the agent context.

---

## 2. Tools

### `lsp`
- **Purpose**: Interacts with the Dart Analysis Server via LSP commands.
- **Commands**:
  - `hover`: Get documentation, signatures, and type info at a specific line and column.
  - `signatureHelp`: Get parameter hints and signature information for a method call.
  - `resolveWorkspaceSymbol`: Fuzzy search for classes, functions, and symbols across the workspace.
- **Example Call (`hover`)**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "lsp",
    "Arguments": {
      "command": "hover",
      "uri": "file:///path/to/project/lib/main.dart",
      "line": 15,
      "column": 10
    }
  }
  ```

---

### `read_package_uris`
- **Purpose**: Reads source code from resolved package dependencies.
- **URI Schemes**:
  - `package:<package_name>/<path>`: Resolves to files inside the package's `lib/` directory.
  - `package-root:<package_name>/<path>`: Resolves to the root of the package directory, enabling access to examples, tests, or config files outside `lib/`.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "read_package_uris",
    "Arguments": {
      "uris": ["package:dartnative/dartnative.dart"]
    }
  }
  ```

---

### `rip_grep_packages`
- **Purpose**: Performs high-speed ripgrep text/regex searches across resolved package dependencies.
- **Parameters**:
  - `query` (required): Search regex or string.
  - `packages` (optional): Subset of package names to search in.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "rip_grep_packages",
    "Arguments": {
      "query": "class NativeBridge"
    }
  }
  ```
