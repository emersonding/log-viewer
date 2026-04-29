# JSON Log Support Design

**Task:** Support JSON file logs with existing log viewer features
**Created:** 2026-04-29
**Status:** Plan

## Summary

Add newline-delimited JSON log support to the existing parser and field extraction pipeline. Each valid JSON object line should become one `LogEntry`, with timestamp, level, message, and custom extracted fields read from JSON properties instead of requiring those values at the beginning of a plain-text log line. Existing search, level filtering, timestamp filtering/sorting, auto-refresh, table rendering, tabs, and custom field columns should continue to work through the current `LogEntry` and `LogViewModel` contracts.

The most important architectural choice is to keep JSON parsing in the parsing/data layer and keep the AppKit table unchanged. The table already renders `lineNumber`, `level`, `timestamp`, `message`, and lazily resolved extracted field values. JSON support should enrich `LogEntry` enough for those existing UI paths to work without creating a second JSON-specific view.

## Current Architecture

The app is a Swift Package macOS app using SwiftUI for shell views and AppKit `NSTableView` for large log rendering.

- `Sources/Services/LogParser.swift` reads `Data`, splits it into lines/chunks, detects new log entries, extracts timestamp and level from line prefixes, and emits `[LogEntry]`.
- `Sources/Models/LogEntry.swift` currently stores `lineNumber`, optional `timestamp`, optional `level`, `message`, and `rawLine`.
- `Sources/ViewModels/LogViewModel.swift` owns parsing, filtering, search, timestamp sorting, auto-refresh, and custom extracted field columns.
- `LogViewModel.extractedFieldValue(named:in:)` currently extracts only logfmt-style `field=value` values from `entry.message` with a regex.
- `Sources/Views/AppKitLogTableView.swift` renders line, level, timestamp, extracted field columns, and message columns from `LogEntry`.

This shape is favorable for JSON support because most existing features already depend on normalized `LogEntry` fields rather than raw parser details.

## Requirements

### Functional

1. Parse newline-delimited JSON logs where each nonblank line is a JSON object.
2. Extract timestamps from JSON fields, not only from raw-line prefixes.
3. Extract log levels from JSON fields and preserve existing aliases:
   `FATAL`, `CRITICAL`, `ERROR`, `WARN`, `WARNING`, `INFO`, `DEBUG`, `TRACE`.
4. Preserve existing log level highlighting and level filtering.
5. Preserve timestamp filtering and timestamp sort.
6. Support custom field extraction from JSON logs:
   - Top-level fields use `field`.
   - Nested fields use dot paths such as `request.user.id`.
   - Array indexes use bracket paths such as `items[0].id` if array traversal is implemented; otherwise arrays are leaf-only and shown as compact JSON strings.
   - Non-leaf object fields are rejected for display as custom columns.
7. Continue supporting existing plain-text/logfmt logs.
8. Treat malformed JSON lines gracefully: do not fail the whole file.
9. Preserve raw-line search behavior so users can still find any raw JSON text.
10. Support incremental refresh for appended JSON lines through the existing parser path.

### Non-Functional

1. Do not change table rendering architecture unless implementation proves it necessary.
2. Keep parsing memory bounded enough for existing large-file expectations.
3. Avoid reparsing whole JSON payloads during every cell render if possible.
4. Add focused unit tests for parser behavior, field extraction, malformed input, nested paths, and non-leaf rejection.
5. Keep plain-text parser behavior backward-compatible.

## Proposed Architecture

### 1. Add Structured Metadata to `LogEntry`

Extend `LogEntry` with an optional structured field store:

```swift
struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let lineNumber: Int
    let timestamp: Date?
    let level: LogLevel?
    let message: String
    let rawLine: String
    let fields: [String: LogFieldValue]
}
```

Add a sendable value enum:

```swift
enum LogFieldValue: Sendable, Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    case nonLeaf
}
```

Store field values in a flattened dictionary keyed by path. Non-leaf objects should be tracked as `.nonLeaf` so the view model can reject or return empty for those paths consistently. Leaf values should be display-ready strings or simple values to avoid repeated JSON traversal in visible cells.

Compatibility impact is low: existing callers can default `fields` to `[:]` in the initializer.

### 2. Detect JSON Object Lines in `LogParser`

Update `isNewLogEntry(_:)` to treat a trimmed line beginning with `{` as a new log entry when it can be parsed as a JSON object. This avoids JSON lines being incorrectly appended as continuations when they do not begin with timestamp or level text.

Implementation detail: avoid double JSON parsing where practical.

- In `parseContent` and chunk parsing, call `parseLine`.
- `parseLine` first attempts `parseJSONLine(line,lineNumber:)` for trimmed object-like lines.
- If JSON parsing succeeds, return a pending entry built from JSON.
- If JSON parsing fails, fall back to the existing prefix-based plain-text parser so malformed lines remain visible.

For newline-delimited JSON, a line with no timestamp/level but valid object content is always a new entry.

### 3. JSON Timestamp Extraction

Support common timestamp field names, checked case-insensitively:

- `timestamp`
- `time`
- `ts`
- `datetime`
- `date`
- `@timestamp`

Accepted timestamp values:

- ISO 8601 strings with `Z`, timezone offsets, and fractional seconds.
- Space-separated datetime strings already supported by the parser.
- Unix epoch seconds or milliseconds as numeric JSON values or numeric strings.

Best-effort behavior:

- If multiple timestamp fields exist, use the first field in the priority list.
- If parsing fails, keep `timestamp = nil` and leave the line visible.
- Do not infer timestamps from nested fields initially unless a common path appears in real logs; nested custom fields still work for display.

### 4. JSON Level Extraction

Support common level field names, checked case-insensitively:

- `level`
- `severity`
- `log_level`
- `loglevel`
- `lvl`
- `priority`

Normalize values by trimming whitespace, uppercasing, and mapping aliases to `LogLevel`.

Additional best-effort mappings:

- `NOTICE` -> `.info`
- `INFORMATION` -> `.info`
- `ERR` -> `.error`
- `WARNING`/`WARN` -> `.warning`
- Numeric syslog-style severity can be deferred unless explicitly needed.

If a JSON level field exists but is an object/array, ignore it.

### 5. JSON Message Extraction

Use the first available string leaf from this priority list:

- `message`
- `msg`
- `log`
- `event`
- `error.message`

If no message-like field exists, use a compact, stable representation of the JSON object as `message`, or use `rawLine` trimmed. The message column should remain useful even when metadata is entirely embedded in JSON.

Do not remove timestamp/level fields from the raw line; search should continue to operate on `rawLine`.

### 6. Flattened Custom Field Extraction

Move custom field extraction behind a format-aware method:

```swift
func extractedFieldValue(named fieldName: String, in entry: LogEntry) -> String
```

Resolution order:

1. If `entry.fields[fieldName]` exists:
   - Return string/number/bool/null display values for leaf fields.
   - Return `""` for `.nonLeaf` to reject object fields.
2. Otherwise, fall back to the current logfmt regex against `entry.message`.

Path rules:

- Object nesting uses `.`: `user.profile.email`.
- Arrays should be handled conservatively:
  - If array contains scalar values, the array path itself is non-leaf by default.
  - If array index paths are implemented, use `items[0].id`.
  - Reject unindexed array/object paths as non-leaf to avoid ambiguous display.
- Field names remain validated by the current regex, but add `[` and `]` only if array index paths are supported.

This keeps existing field-column UI and tab persistence intact.

### 7. Malformed and Multi-Line JSON

Initial scope should support newline-delimited JSON, not pretty-printed multi-line JSON objects. Supporting multi-line JSON would conflict with current continuation-line semantics and requires object-boundary tracking across chunks.

Behavior:

- Valid single-line JSON object: parse as one entry.
- Malformed object-like line: show as plain text entry if possible, or append according to existing continuation rules.
- JSON array at top level: treat as plain text unless there is a clear product need to split array elements into entries.
- Pretty-printed JSON: out of scope for first iteration; it will display as plain text/multiline based on existing rules.

## Feasibility

Feasible with low-to-moderate risk. Foundation's `JSONSerialization` can parse per-line JSON without adding dependencies. The parser is already actor-isolated and chunk-based, so JSON parsing can be introduced inside the existing parsing pipeline.

The main risk is performance on very large files. Per-line JSON parsing is more expensive than regex prefix parsing. Flattening metadata once during parse avoids cell-render reparsing, but it increases memory per entry. The design therefore keeps flattened values compact and bounded to leaf paths actually present in each record.

If large JSON files regress beyond acceptable load times, the fallback plan is to optimize in this order:

1. Fast precheck: only attempt JSON parsing for trimmed lines starting with `{` and ending with `}`.
2. Parse only metadata fields first if possible.
3. Flatten lazily on first custom field access with a per-entry cache or shared field path resolver.
4. Add a parser mode detector for files where the first N nonblank lines are JSON, so object-like malformed lines can be handled predictably.

## System Cost

### Implementation Cost

Estimated size: 1-2 engineering days.

- `LogEntry` model extension: small.
- `LogParser` JSON branch, flattening, timestamp/level/message extraction: medium.
- `LogViewModel` extracted field resolver update: small.
- Tests and fixtures: medium.
- Documentation/README update: small.

### Runtime Cost

- CPU: JSON parsing adds per-line decoding cost for JSON lines only.
- Memory: flattened fields increase memory per JSON entry. A typical log with 10-30 leaf fields per entry is acceptable for moderate files but can be expensive at multi-million-row scale.
- UI: no expected table rendering cost increase if field values are flattened at parse time.

### Maintenance Cost

Low if JSON support is isolated in `LogParser` helper methods and `LogFieldValue`. Avoid spreading JSON-specific checks through views.

## Test Plan

Add tests primarily in `Tests/LogParserTests.swift` and `Tests/LogViewModelTests.swift`.

Parser tests:

- Parses JSON line with `timestamp`, `level`, and `message`.
- Parses aliases: `time`, `ts`, `severity`, `msg`.
- Parses nested fields and flattens as `a.b.c`.
- Keeps non-leaf object paths rejected.
- Handles string, number, bool, and null leaf values.
- Handles invalid JSON without throwing and without dropping the line.
- Keeps plain-text log parsing unchanged.
- Treats JSON lines without timestamp/level as separate entries.

View model tests:

- `extractedFieldValue` returns flattened JSON leaf values.
- `extractedFieldValue` returns empty string for non-leaf JSON object paths.
- JSON field extraction falls back to logfmt for plain-text entries.
- Existing field name validation covers dot paths and rejects unsafe names.

Integration-style tests:

- Opening a `.jsonl` fixture applies level filters.
- Timestamp range filtering works on parsed JSON timestamps.
- Incremental refresh appends new JSON lines correctly.

## Rollout Plan

1. Extend `LogEntry` with `fields` and `LogFieldValue`, defaulting to empty fields.
2. Add JSON object parse helpers to `LogParser`.
3. Wire timestamp, level, message, and flattened field extraction in the JSON branch.
4. Update `LogViewModel.extractedFieldValue` to prefer structured fields and reject non-leaf fields.
5. Add unit tests and JSON fixtures.
6. Update README feature list and testing notes.
7. Run `swift test`; optionally run `./build_app.sh` for app-level confidence.

## Decisions

- Support newline-delimited JSON first; pretty-printed multi-line JSON is out of scope.
- Keep `NSTableView` rendering unchanged.
- Flatten JSON fields during parse so custom field columns do not parse JSON during cell rendering.
- Reject object-valued custom fields by returning an empty value for non-leaf paths.
- Preserve raw JSON in `rawLine` for search and copy/paste fidelity.
- Keep plain-text/logfmt behavior as a fallback and compatibility path.

## Open Questions Resolved by Assumption

- **Which JSON timestamp fields are supported?** Use a prioritized common-name list: `timestamp`, `time`, `ts`, `datetime`, `date`, `@timestamp`.
- **Which JSON level fields are supported?** Use common names: `level`, `severity`, `log_level`, `loglevel`, `lvl`, `priority`.
- **Should nested custom fields use dot notation?** Yes, as required: `a.b.c`.
- **Should non-leaf custom fields be rejected?** Yes. Return empty values for object/array paths unless an indexed leaf path is explicitly supported.
- **Should top-level JSON arrays be parsed?** No for the first implementation.
- **Should malformed JSON fail the file load?** No. Keep the line visible and continue.

## Acceptance Criteria

The implementation is complete when:

- A JSONL file with embedded timestamp and level fields displays correct timestamp and level columns.
- Level highlighting and level filters work for JSON logs.
- Timestamp filtering and sorting work for JSON logs.
- Adding a custom field column such as `request.id` displays nested JSON leaf values.
- Adding a custom field column for an object path such as `request` displays empty values rather than serialized object blobs.
- Existing plain-text/logfmt tests still pass.
- `swift test` passes.
