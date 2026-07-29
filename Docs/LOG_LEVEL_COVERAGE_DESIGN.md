# Log Level Coverage & UNDEFINED Bucket Design

**Task:** Capture log levels the parser currently misses (starting with `SEVERE`), and guarantee no line is invisible to the level filter
**Created:** 2026-07-29
**Status:** Plan
**Method:** Claude Code interactive design discussion (no plan mode / no superpowers)
**Branch:** `feat/severe-level-and-undefined-bucket`

## Summary

Three changes, driven by one principle: **a wrong level guess must never damage the message text, and an unrecognized level must never make a line unfilterable.**

1. Add `SEVERE` (java.util.logging) as a recognized level keyword mapping to `.error`. Deliberately *not* adding the other ~30 candidate keywords surveyed.
2. Stop consuming the level keyword from `message`. The level becomes a pure *annotation* derived from the line rather than a token cut out of it. Timestamps continue to be consumed.
3. Add a real `LogLevel.undefined` case surfaced in the level selector alongside FATAL/ERROR/WARNING/etc., so lines with no detected level can be explicitly shown or hidden.

## Problem

### Defect 1 — `SEVERE` is not recognized at all

`Sources/Services/LogParser.swift:21`

```swift
private let logLevelRegex = try! NSRegularExpression(
    pattern: #"^\[?(FATAL|CRITICAL|ERROR|WARN|WARNING|INFO|DEBUG|TRACE)\]?"#,
    options: .caseInsensitive)
```

`SEVERE` appears in neither the regex nor `levelMap` (`LogParser.swift:773`). The impact is larger than a missing color: `hasLogLevelAtStart()` (`LogParser.swift:317`) reuses this same regex to decide whether a line **starts a new entry**. A bare `SEVERE: connection refused` line with no timestamp therefore fails the entry-start test and is appended to the previous entry as a continuation line. The line effectively disappears from the table rather than merely losing its level.

### Defect 2 — level keywords match as prefixes and corrupt the message

The regex has no trailing boundary, so every keyword matches as a prefix and `extractLogLevel` (`LogParser.swift:724`) then consumes the matched span from the line. Verified against the live pattern:

```
"WARNING - disk almost full"     → matched 'WARN',  message becomes 'ING - disk almost full'
"INFORMATION about the release"  → matched 'INFO',  message becomes 'RMATION about the release'
"ERRORS: 5 total"                → matched 'ERROR', message becomes 'S: 5 total'
"Debugging session started"      → matched 'Debug', message becomes 'ging session started'
```

`WARNING` never reaches `levelMap` — `WARN` wins the alternation first and eats four characters off the message. `Tests/LogParserTests.swift:86` (`testParseAllLogLevels`) feeds a `WARNING` line but only asserts `entries[n].level`, never `.message`, which is why this has gone unnoticed.

### Defect 3 — unleveled entries bypass the level filter

`Sources/ViewModels/LogViewModel.swift:470` and `:500`

```swift
if let level = entry.level, !levels.contains(level) { return false }
```

`level == nil` always passes. Unparsed lines can never be hidden — clicking "None" (`FilterBar.swift:105`) still shows them, and there is no control for them at all. Same root cause as Defect 1: unknown levels aren't representable in the filter model, so they're hardcoded to one behavior.

## Decisions & Tradeoffs

### Decision 1 — Add only `SEVERE`

A survey produced ~30 candidate keywords across java.util.logging, syslog, Go zap, Android logcat, zerolog, PostgreSQL, winston, and loguru, tiered by collision risk. **Final decision: add `SEVERE` only; skip all others**, including the low-risk Tier A entries (`PANIC`, `DPANIC`, `EMERG`, `VERBOSE`, `EXCEPTION`).

*Rationale:* `SEVERE` is the concrete, observed miss. Every additional keyword widens the false-positive surface on `hasLogLevelAtStart()`, which controls entry splitting — the most damaging failure mode in the app. With the `UNDEFINED` bucket (Decision 3) in place, the cost of *not* recognizing a level drops sharply: the line stays visible, stays filterable, and keeps its full text. That asymmetry justifies a conservative list.

*Tradeoff accepted:* JUL's `FINE`/`FINER`/`FINEST`/`CONFIG`, syslog's `ALERT`/`CRIT`/`EMERG`, and Go's `PANIC` remain unrecognized and will land in `UNDEFINED`. This is a known, revisitable gap — not an oversight. The tier tables below are retained so a future expansion doesn't have to redo the survey.

*Rejected alternative:* adding all Tier A + Tier B keywords with per-tier guards (ALL-CAPS + punctuation delimiter requirements). Correct but more machinery than the evidence currently justifies.

### Decision 2 — Never consume the level keyword from `message`

The level keyword stays in `message`. Timestamps continue to be consumed.

*Rationale:* the two fields have different reliability. A timestamp match is structurally unambiguous, and leaving it in duplicates it against the dedicated timestamp column, hurting readability. A level match is a heuristic keyword guess against arbitrary text. Since the guess can be wrong, it must be non-destructive — the user should always be able to read the complete original message even when the level is mislabeled.

*Consequence:* this alone neutralizes the *corruption* half of Defect 2. `"Debugging session started"` may still be mislabeled `.debug`, but the text stays intact and the mistake is cosmetic and self-evident to the reader.

*Tradeoff accepted:* the level string is now visually duplicated between the Level column and the Message column. Judged acceptable — and arguably an improvement, since `SyntaxHighlighter.highlightLogLevel` (`SyntaxHighlighter.swift:191`) already highlights against `rawLine` and was previously coloring a token that no longer appeared in the rendered message.

*Open sub-decision (defaulting to "keep"):* the IntelliJ branch at `LogParser.swift:339-350` currently discards bracketed context tokens (`[3733055]`) along with the level. Those aren't a parsed field — just dropped text. Under the "message stays complete" principle they should be kept, yielding `message = "[3733055]   WARN - Foo - msg"`. Noisier but consistent. Flag if the special case is preferred.

### Decision 3 — `UNDEFINED` as a first-class level in the selector

`LogLevel.undefined` sits in the level selector next to WARN/ERROR/etc. rather than being a hidden implicit behavior.

*Implementation choice:* keep `LogEntry.level` as `LogLevel?` and map `nil → .undefined` **only at the filter boundary**, rather than assigning `.undefined` at parse time.

```swift
if !levels.contains(entry.level ?? .undefined) { return false }
```

*Rationale:* `nil` keeps `SyntaxHighlighter` and the table's level cell (`AppKitLogTableView.swift:402`) from badging or coloring plain lines, which is the correct appearance. `UNDEFINED` is a *filter bucket*, not a rendering state. Assigning it at parse time would leak a synthetic value into every rendering path.

*Tradeoff accepted:* the `nil`/`.undefined` duality means the mapping must be applied consistently at each filter site. There are exactly two (`LogViewModel.swift:470`, `:500`) plus `StatusBarView.swift:104`.

### Decision 4 — Add the trailing-word-boundary guard

Append `(?![A-Za-z0-9_])` to the keyword capture group, and order alternatives longest-first.

*Rationale:* Decision 2 stops prefix matches from corrupting text, but it does not stop them from producing a **wrong level** or, worse, a **false entry split** via `hasLogLevelAtStart()`. `"Debugging session started"` should not be tagged `.debug` and should not begin a new entry. This is a standalone correctness fix that also makes `WARNING` and `INFORMATION` reach `levelMap` for the first time.

*Tradeoff accepted:* this changes level assignment for lines that previously matched by prefix. Any log line genuinely beginning `DEBUGxyz` would lose its level — such lines land in `UNDEFINED`, which is the desired conservative outcome.

## Implementation Plan

### `Sources/Models/LogEntry.swift`

- Add `case undefined = "UNDEFINED"` to `LogLevel`.
- `color` / `nsColor`: secondary/tertiary label gray, visually recessive against real levels.
- `iconName`: `"questionmark.circle"`.
- `backgroundColor`: `nil`; `foregroundColor` falls through to `color`.
- Place the case so `allCases` ordering stays sensible, but do not rely on `allCases` order for UI — `FilterBar` uses an explicit array.

### `Sources/Services/LogParser.swift`

- Build the regex alternation from a single source-of-truth alias table rather than hand-writing the keyword list twice. The `WARN`/`WARNING` ordering bug exists precisely because the regex (`:21`) and `levelMap` (`:773`) were authored separately and drifted.
- Add `"SEVERE": .error` to that table.
- New pattern shape: `^\[?(<alternation, longest-first>)\]?(?![A-Za-z0-9_])`.
- Split `extractLogLevel(_:inout)` (`:724`) into a **detect-only** function returning `(LogLevel?, matchedRange)` that does not mutate its input. Timestamp extraction at `:331` is unchanged and still consumes.
- `parseLine` (`:323`): `message` is now everything after the timestamp. The bracket-probe loop at `:339-350` no longer reassigns `remaining`, it only resolves the level.
- Delete `strippingLeadingSeparator` (`:757`) and its call at `:354` — the `-`/`:`/`|` after a level now belongs to the message. Confirm no other caller before removing.
- `logLevel(for:)` remains shared with `parseJSONLogLevelValue` (`:459`). Note that the JSON path has **zero** false-positive risk (the value comes from a designated `level` field), so the alias table may stay generous there while the regex alternation stays strict. `ERR` and `NOTICE` already behave this way today — map-only and unreachable from text. Make that split deliberate and comment it.

### `Sources/Models/FilterState.swift`

- `enabledLevels` default already uses `Set(LogLevel.allCases)`, so `.undefined` is enabled by default and current behavior is preserved for new state.
- **Migration required.** `FilterState` is `Codable` and persisted per-file inside `OpenedFile` → `OpenedFilesWorkspace` in `UserDefaults` (`LogViewModel.swift:908` encode, `:1022` decode). Sets saved before this change contain no `.undefined`, so on upgrade users would silently start hiding all unleveled lines. Add a custom `init(from:)` that inserts `.undefined` when decoding a set that lacks it.
- `isDefault` compares against `LogLevel.allCases.count` and keeps working once `.undefined` is in `allCases`.

### `Sources/ViewModels/LogViewModel.swift`

- `performFiltering()` `:470` and `performFilteringSynchronous()` `:500`: replace the `if let level` guard with `if !levels.contains(entry.level ?? .undefined) { return false }`.

### `Sources/Views/FilterBar.swift`

- Add `.undefined` to the explicit array at `:47`. Order: `[.fatal, .error, .warning, .info, .debug, .trace, .undefined]` — trailing, after the severity-ordered real levels.
- `selectAllLevels()` (`:99`) and the presets at `:159`/`:175` use `Set(LogLevel.allCases)` and pick it up automatically. The `[.error, .warning, .info]` preset at `:167` intentionally excludes it.

### `Sources/Services/SyntaxHighlighter.swift`

- The `for level in LogLevel.allCases` loop at `:41` would compile a `\[?UNDEFINED\]?` regex that only ever matches literal text. Skip `.undefined` in that loop.
- `highlight()` at `:65` is already `if let level = entry.level`, so `nil` entries are untouched. No change.

### `Sources/Views/StatusBarView.swift`

- `filterIndicator` at `:104` compares against `Set(LogLevel.allCases)` and will now list `UNDEFINED` among disabled levels when toggled off. Correct as-is; verify the string reads well.

### `Sources/Views/AppKitLogTableView.swift`

- `makeLevelCell` at `:365` takes `LogLevel?` and already renders an empty cell for `nil`. No change — `.undefined` is never assigned to an entry.

## Test Plan

New and updated tests in `Tests/LogParserTests.swift` and `Tests/LogViewModelTests.swift`:

1. **`SEVERE` end-to-end** — JUL-shaped fixture (`SEVERE: msg`, `INFO: msg`, no timestamps) asserting both the **entry count** (proves the entry-boundary fix — previously `SEVERE` lines were swallowed as continuations) and the level mapping to `.error`.
2. **Message completeness** — extend `testParseAllLogLevels` (`:86`) to assert `.message`, which it currently never does. `"2026-04-13T10:30:02Z WARNING Warning message"` must yield `message == "WARNING Warning message"` and `level == .warning`.
3. **Separator retention** — `"... WARN - Foo - msg"` yields `message == "WARN - Foo - msg"`.
4. **Timestamp still consumed** — message must not contain the timestamp.
5. **Boundary guard** — `"Debugging session started"` and `"INFORMATION about the release"` produce `level == nil` and an unmodified message; assert they do not create spurious entry splits.
6. **`UNDEFINED` filtering** — unleveled entries are hidden when `.undefined` is removed from `enabledLevels`, shown when present, and hidden by "None".
7. **Persistence migration** — decode a `FilterState` JSON payload in the pre-change shape (no `UNDEFINED` in the set) and assert `.undefined` is present afterward.
8. **IntelliJ format** — the existing IntelliJ case keeps its level and now retains the keyword in `message`; locks in the bracket-token sub-decision either way.

## Deferred / Not Doing

Retained so a future expansion doesn't redo the survey. **None of these are being added now.**

**Tier A — low collision risk, would go in both regex and map**

| Keyword | → | Source |
|---|---|---|
| `PANIC` | fatal | Go, PostgreSQL |
| `DPANIC` | fatal | Go zap |
| `EMERG` / `EMERGENCY` | fatal | syslog, nginx, Apache |
| `VERBOSE` | trace | Serilog, Android |
| `EXCEPTION` | error | various |

**Tier B — English-word collisions; would need ALL-CAPS + trailing `:`/`]`/`|` in the regex**

| Keyword | → | Collision |
|---|---|---|
| `CONFIG` | debug | "Configuration loaded" |
| `FINE` | debug | "Fine tuning model" |
| `FINER` / `FINEST` | trace | same family |
| `ALERT` | fatal | "Alerting rules loaded" |
| `CRIT` | fatal | "Critical path…" |
| `LOG` | info | "Logging started" — very high |
| `SUCCESS` | info | "Successfully connected" |
| `AUDIT` | info | "Audit trail written" |

**Tier C — recommended against regardless**

| Keyword | Why |
|---|---|
| `V` `D` `I` `W` `E` `F` (logcat) | bare `I` splits any continuation line starting with "I "; would require matching the full `^[VDIWEF]/\w+\(\s*\d+\):` shape |
| `INF` `WRN` `DBG` `TRC` `FTL` `PNC` (zerolog) | `INF` hits "Infrastructure" |
| `NOTSET` (Python) | semantically *is* undefined — served by the `UNDEFINED` bucket |
| `HTTP` `SILLY` (winston) | `HTTP` collides constantly |
| `trace1`…`trace8` (Apache) | would be covered by `\d?` on `TRACE` |

## Commit Sequencing

Three commits, so a message-rendering regression stays bisectable:

1. `fix:` trailing-boundary guard + single-source alias table + the message assertions the tests were missing. Changes existing message output on its own.
2. `feat:` stop consuming the level keyword from `message`; drop `strippingLeadingSeparator`.
3. `feat:` add `SEVERE`, add `LogLevel.undefined`, filter mapping, FilterBar entry, `FilterState` decode migration.

Then a `chore:` version bump (minor — this is a feature-bearing change).
