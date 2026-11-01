# Device Management & Application Execution

This guide covers discovering devices, launching DartNative applications, reading logs, and stopping background app processes.

---

## 1. Overview

DartNative projects run on devices and emulators using `dn run`. The `dartnative` MCP server manages running processes asynchronously and assigns process IDs (`pid`) to track logs and stop running apps.

---

## 2. Tools

### `dn_devices`
- **Purpose**: Lists all available physical devices, emulators, simulators, and desktop targets.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_devices",
    "Arguments": {}
  }
  ```

---

### `dn_run`
- **Purpose**: Launches the application on a target device using `dn run`.
- **Behavior**: Runs asynchronously, keeps the process alive, and returns `pid`, `ready`, and initial startup output.
- **Parameters**:
  - `deviceId` (optional): The ID of the target device from `dn_devices`.
  - `roots` (optional): Project root URI.
  - `target` (optional): Path to the entrypoint file (e.g., `lib/main.dart`).
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_run",
    "Arguments": {
      "deviceId": "macos"
    }
  }
  ```

---

### `dn_app_logs`
- **Purpose**: Reads recent stdout/stderr lines from an application started by `dn_run`.
- **Parameters**:
  - `pid` (required): The integer process ID returned by `dn_run`.
  - `lines` (optional): Number of recent lines to retrieve.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_app_logs",
    "Arguments": {
      "pid": 12345,
      "lines": 50
    }
  }
  ```

---

### `dn_stop_app`
- **Purpose**: Stops a running application process previously launched with `dn_run`.
- **Rule**: Always stop running applications when testing or debugging completes so system and device resources are freed.
- **Parameters**:
  - `pid` (required): The integer process ID of the app to stop.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_stop_app",
    "Arguments": {
      "pid": 12345
    }
  }
  ```

---

### `dn_install`
- **Purpose**: Installs the compiled application package directly onto a target device without starting a live session.
- **Parameters**:
  - `deviceId` (optional): Target device ID.
  - `roots` (optional): Project root URI.
