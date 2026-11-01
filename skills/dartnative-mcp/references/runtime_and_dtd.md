# Runtime Diagnostics & Dart Tooling Daemon (DTD)

This guide covers discovering and connecting to the Dart Tooling Daemon (DTD), triggering hot reload and hot restart, and capturing runtime errors.

---

## 1. Overview

Tools that interact with a running application (`hot_reload`, `hot_restart`, `get_runtime_errors`) require an active connection to the Dart Tooling Daemon (DTD).

---

## 2. Tools

### `dtd`
- **Purpose**: Manages connections to the Dart Tooling Daemon.
- **Commands**:
  - `listDtdUris`: Discovers active DTD WebSocket URIs.
  - `connect`: Connects the MCP server to a chosen DTD URI.
  - `listConnectedApps`: Lists applications currently connected to the DTD.
- **Workflow**:
  1. Find URI:
     ```json
     {
       "ServerName": "dartnative",
       "ToolName": "dtd",
       "Arguments": {
         "command": "listDtdUris"
       }
     }
     ```
  2. Connect:
     ```json
     {
       "ServerName": "dartnative",
       "ToolName": "dtd",
       "Arguments": {
         "command": "connect",
         "uri": "ws://127.0.0.1:58585/token="
       }
     }
     ```

---

### `hot_reload`
- **Purpose**: Applies code modifications to the running application without losing application state.
- **When to use**: Changes to widget build methods, styling, layout, or functions inside UI widgets.
- **Parameters**:
  - `appId` (optional): ID of the connected app (if multiple apps run).
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "hot_reload",
    "Arguments": {}
  }
  ```

---

### `hot_restart`
- **Purpose**: Restarts the running application and re-initializes all state, rerun `main()`.
- **When to use**: Changes to `initState`, `dispose`, global/static variables, `const` constructors, or app lifecycle setup.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "hot_restart",
    "Arguments": {}
  }
  ```

---

### `get_runtime_errors`
- **Purpose**: Retrieves recent runtime exceptions, stack traces, and unhandled errors from the running app.
- **Parameters**:
  - `appId` (optional): Connected application ID.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "get_runtime_errors",
    "Arguments": {}
  }
  ```
