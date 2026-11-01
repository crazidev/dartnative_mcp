# Package Search & Discovery (`dartpub_search` & `pub_dev_search`)

This guide covers finding packages before adding them, and inspecting a DartNative plugin in depth. For resolving, adding, and upgrading dependencies see [`dependencies_and_pub.md`](./dependencies_and_pub.md).

---

## 1. Two Registries, Two Tools

The `dartnative` MCP server exposes two independent search tools. They hit **different registries** and are not interchangeable.

| Registry | Tool | Contains | Use for |
| :--- | :--- | :--- | :--- |
| `dartpub.dev` | `dartpub_search` | The **DartNative plugin registry** (`/api/plugins`) | Native DartNative plugins: camera, bottomsheet, app links, permissions, maps, SQLCipher, … |
| `pub.dev` | `pub_dev_search` | The **general Dart package registry** | Ordinary pure-Dart packages: `http`, `path`, `json_annotation`, `test`, … |

> **Critical rule:** `dartpub_search` does **not** search pub.dev packages. A query for `http` there returns `dartnative_http` / `posthog_kit` — never the real `http` package. If you need a general package, call `pub_dev_search`.

Rule of thumb:

- Building a **native capability** (camera, sheet, notifications, device APIs) → `dartpub_search`.
- Building **Dart logic** (parsing, HTTP, state, codegen) → `pub_dev_search`.
- Unsure → search `dartpub_search` first, then fall back to `pub_dev_search`.

---

## 2. `dartpub_search`

Searches the DartNative plugin catalog, or fetches full metadata and docs for one plugin.

### Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `query` | string | – | Keywords to search the catalog. Omit to browse the catalog. |
| `name` | string | – | Exact plugin name to inspect. Mutually exclusive with `query`. |
| `detail` | enum | – | With `name` only: `info` (default), `readme`, `example`, `changelog`. |
| `owner` | string | – | Filter by GitHub owner, e.g. `DartNative`, `crazidev`. |
| `sort` | enum | – | `name` (default), `installs`, `active_apps`, `upvotes`, `created`. |
| `status` | enum | – | `published` (default), `archived`, `all`. |
| `limit` | int | – | Results per page, `1`–`100` (default `10`). |
| `page` | int | – | Page number, starting at `1` (default `1`). |
| `raw` | bool | – | Append the raw registry JSON. Off by default; it is large. |

### Output

A single Markdown document:

- A header with the **total** match count and the page window.
- One section per plugin with version, tagline, truncated description, license, runtime, source (`bundled with the SDK` vs `published package`), publisher, install stats, and links.
- A footer explaining how to inspect or install a result.
- `Next page: \`page: N\`.` when more results exist.

### Examples

Search the catalog:

```json
{
  "ServerName": "dartnative",
  "ToolName": "dartpub_search",
  "Arguments": { "query": "bottom sheet" }
}
```

Browse the most popular plugins:

```json
{
  "ServerName": "dartnative",
  "ToolName": "dartpub_search",
  "Arguments": { "sort": "installs", "limit": 20 }
}
```

List everything owned by an organization:

```json
{
  "ServerName": "dartnative",
  "ToolName": "dartpub_search",
  "Arguments": { "owner": "DartNative", "limit": 100 }
}
```

Inspect a specific plugin:

```json
{
  "ServerName": "dartnative",
  "ToolName": "dartpub_search",
  "Arguments": { "name": "native_bottomsheet" }
}
```

Read its README before writing integration code:

```json
{
  "ServerName": "dartnative",
  "ToolName": "dartpub_search",
  "Arguments": { "name": "native_bottomsheet", "detail": "readme" }
}
```

### Notes and limits

- **`name` and `query` are mutually exclusive.** Sending both is rejected; pick one.
- **`detail` requires `name`.** `detail: "readme"` alone is rejected — it only makes sense for a single plugin.
- **Paging is enforced locally.** `limit` outside `1`–`100` and `page` below `1` fail schema validation before any network call.
- **Out-of-range pages are reported as such**, not as "no matches". Lower the `page` when you see `No plugins on page N`.
- **Only the registry's keyword search is used.** There is no boolean `OR`; run multiple searches instead.
- **Leave `raw` off** unless you need a field the summary does not surface. It can inflate a response from ~3 KB to ~100 KB and flood the context window.

---

## 3. `pub_dev_search`

Searches pub.dev for ordinary Dart packages and returns scored metadata.

### Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `query` | string | yes | pub.dev search expression. |

### Query syntax

| Expression | Meaning |
| :--- | :--- |
| `retry` | Freeform keyword search. |
| `"exact phrase"` | Only packages containing that exact phrase. |
| `dependency:http` | Packages that **declare** `http` in their `pubspec.yaml`. |
| `dependency*:http` | Packages that depend on `http`, directly or transitively. |
| `topic:http` | Packages tagged with the `http` topic. |
| `publisher:google.dev` | Packages published by a given publisher. |
| `sdk:dart` | Packages supporting a given SDK. |
| `runtime:web` \| `native-jit` \| `native-aot` | Packages supporting a given runtime. |
| `updated:3d` \| `2w` \| `6m` \| `2y` | Packages updated within that window. |
| `has:executable` | Packages with files in `bin/`. |

There is no `OR` operator — issue separate searches for alternatives.

### Output

Up to **10** results (no paging). Each result is its own JSON content block:

```json
{
  "packageName": "retry",
  "latestVersion": "3.1.2",
  "description": "…",
  "homepage": "…",
  "repository": "…",
  "documentation": "…",
  "libraries": { "retry": "https://pub.dev/documentation/retry/latest/retry/" },
  "scores": { "pubPoints": 160, "maxPubPoints": 160, "likes": 120, "downloadCount": 50000 },
  "topics": ["topic:network", "topic:http"],
  "licenses": ["license:apache-2.0"],
  "publisher": "publisher:google.dev"
}
```

Use `scores.pubPoints`, `scores.likes`, `scores.downloadCount`, and `publisher` to judge whether a package is healthy. A `publisher:` tag is a strong trust signal; a missing one is not necessarily disqualifying.

### Examples

Find an HTTP client with retries:

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub_dev_search",
  "Arguments": { "query": "http client retry" }
}
```

Find packages that already depend on `dartnative`:

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub_dev_search",
  "Arguments": { "query": "dependency*:dartnative" }
}
```

---

## 4. Recommended Workflows

### 4.1 Add a native capability

1. `dartpub_search` with a feature `query` (e.g. `"camera"`).
2. Pick a result — prefer higher `active apps`/`weekly installs`, a `Publisher`, and `Source: published package` unless the SDK copy is what you want.
3. `dartpub_search` with `name` + `detail: "readme"` to read usage docs.
4. Add it with `pub`:

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": { "command": "add", "packageNames": ["dartnative_camera"] }
}
```

5. Run `analyze_files`, then `pub` with `command: "get"` if resolution was not automatic.

### 4.2 Add a pure-Dart package

1. `pub_dev_search` with a keyword query.
2. Compare `scores`, `publisher`, and `latestVersion`.
3. Add with `pub` `command: "add"` and `packageNames`.

### 4.3 Verify a package name before adding

If the name is uncertain, run `dartpub_search` with `name` first. A `404` returns an actionable error instead of silently adding a wrong dependency. For pub.dev packages, use `pub_dev_search` and match on `packageName` exactly.

### 4.4 Check for alternatives

There is no `OR` operator in either tool. Run several `query` values (or `topic:` / `dependency:` expressions) and compare the result sets.

### 4.5 Inspect an installed dependency's source

Search tools only describe packages. To read actual code, use `read_package_uris` (`package:` / `package-root:` schemes) or `rip_grep_packages`. See [`code_intelligence.md`](./code_intelligence.md).

---

## 5. Common Mistakes

| Mistake | Result | Fix |
| :--- | :--- | :--- |
| Using `dartpub_search` for `http`, `path`, `json` | Only DartNative plugins are returned | Use `pub_dev_search`. |
| Sending `name` and `query` together | Rejected as conflicting arguments | Send one. |
| Sending `detail` without `name` | Rejected — detail is per-plugin | Add `name`, or drop `detail`. |
| Passing `limit: 500` | Schema validation error (max `100`) | Page with `page` instead. |
| Passing `page: 0` | Schema validation error (min `1`) | Pages start at `1`. |
| Reading page 99 of a 5-result search | "No plugins on page N" | Lower `page`. |
| Leaving `raw: true` on | Response balloons to tens of KB | Omit `raw`. |
| Assuming 10 results is everything | `pub_dev_search` is capped at 10 | Refine the query. |

---

## 6. Installing What You Found

`dartpub_search` and `pub_dev_search` only search. Installing always goes through the `pub` tool:

```json
{
  "ServerName": "dartnative",
  "ToolName": "pub",
  "Arguments": {
    "command": "add",
    "packageNames": ["native_bottomsheet"]
  }
}
```

`packageNames` also accepts pub descriptors:

- `"dev:pkg_name"` — dev dependency
- `"override:pkg_name:1.0.0"` — dependency override
- `"pkg_name:{git:{url: https://github.com/o/r.git, ref: main, path: subdir}}"`
- `"pkg_name:{path: ../pkg_name}"`

Entries that start with `-` are rejected, so `packageNames` cannot be used to smuggle CLI flags.

After adding, re-run `analyze_files` and `dart_format` as required by the main skill rules.
