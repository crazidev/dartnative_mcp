# Building, Testing & Toolchain Diagnostics

This guide covers compiling release artifacts, running test suites, and diagnosing the DartNative environment.

---

## 1. Overview

DartNative projects use `dn build` to produce target platform artifacts and `dn test` to run automated tests.

---

## 2. Tools

### `dn_build`
- **Purpose**: Compiles a release artifact for the specified platform target.
- **Supported targets**: `apk`, `appbundle`, `aar`, `ios`, `ipa`, `macos`, `linux`, `windows`, `web`.
- **Parameters**:
  - `target` (required): Target build platform (e.g. `apk`, `macos`, `ios`).
  - `roots` (optional): Project root URI.
  - `args` (optional): Extra CLI arguments forwarded to `dn build`.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_build",
    "Arguments": {
      "target": "macos"
    }
  }
  ```

---

### `run_tests`
- **Purpose**: Runs `dn test` with `package:test` arguments across the project or for specific test files.
- **Parameters**:
  - `roots` (optional): Project roots or file paths to test.
  - `args` (optional): Extra test arguments (e.g. `--name`, `--plain-name`).
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "run_tests",
    "Arguments": {}
  }
  ```

---

### `dn_clean`
- **Purpose**: Cleans build caches, ephemeral artifacts, and generated files (`dn clean`).
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_clean",
    "Arguments": {}
  }
  ```

---

### `dn_doctor`
- **Purpose**: Diagnoses the DartNative toolchain, SDK installation, dependencies, and environment configuration.
- **Example Call**:
  ```json
  {
    "ServerName": "dartnative",
    "ToolName": "dn_doctor",
    "Arguments": {}
  }
  ```

---

### `create_project`
- **Purpose**: Creates a new DartNative or Dart project using `dn create`.
- **Parameters**:
  - `projectType` (required): `"dartnative"` or `"dart"`.
  - `directory` (required): Target directory name.
  - `template` (optional): Template name.
