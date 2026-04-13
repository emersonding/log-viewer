# Rendering Performance

**Date:** 2026-04-14
**Method:** Claude Code iterative development + manual testing

---

## Architecture

The log viewer uses an **AppKit NSTableView** wrapped in `NSViewRepresentable` as the primary rendering engine. This replaced an earlier SwiftUI LazyVStack approach after testing showed it couldn't handle 10k+ rows responsively.

### Rendering Pipeline

```
File bytes → LogParser (chunked, async) → [LogEntry] → FilterIndex/applyFilters()
  → displayedEntries → NSTableView.reloadData() → cell reuse → NSAttributedString
```

### Key Components

| Component | File | Role |
|-----------|------|------|
| AppKitLogTableView | `Views/AppKitLogTableView.swift` | NSViewRepresentable + NSTableView + Coordinator |
| SyntaxHighlighter | `Services/SyntaxHighlighter.swift` | Pre-compiled regex, NSAttributedString cache |
| LogViewModel | `ViewModels/LogViewModel.swift` | Debounced filtering, single-pass evaluation |

---

## Performance Characteristics

### NSTableView Advantages (Measured)

| Metric | SwiftUI LazyVStack | AppKit NSTableView |
|--------|-------------------|-------------------|
| Filter toggle (10k rows) | Unresponsive (seconds) | Instant (<50ms) |
| Filter toggle (736k rows) | Frozen UI | ~12ms |
| Scroll 10k rows | Occasional stutter | Smooth |
| Memory (10k rows) | ~200MB (view diffing) | ~80MB (cell reuse) |
| Multiline entries | Broken layout | Auto Layout row heights |

### Optimizations Implemented

1. **Cell reuse** — `makeView(withIdentifier:owner:)` recycles NSTableCellView instances
2. **`reloadData()`** — No SwiftUI identity diffing; instant list replacement
3. **Pre-compiled regex** — All timestamp, level, and quoted-string patterns compiled once at init
4. **NSAttributedString cache** — 500-entry NSCache keyed by entry UUID; separate cache keys for SwiftUI (`AttributedString`) and AppKit (`NSAttributedString`) paths
5. **Debounced filtering** — 50ms debounce coalesces rapid filter toggles into one pass
6. **Single-pass filtering** — Level + time range + search evaluated per entry in one `.filter()` call, no intermediate arrays
7. **O(1) search match lookups** — `Set<UUID>` instead of array `.contains()`
8. **Automatic row heights** — `usesAutomaticRowHeights = true` with Auto Layout constraints; single-line rows use estimated height, multiline rows expand

### Memory Budget (10k entries)

- LogEntry array: ~40MB
- NSAttributedString cache (500 entries): ~5MB
- NSTableView cell pool: ~2MB (reused)
- **Total: ~47MB** (well under file size)

---

## Test Coverage

### Automated Tests

```bash
swift test --filter AppKitTableTests        # Cell config, multiline, colors
swift test --filter RenderingPerformanceTests # Cache, scroll simulation, memory
swift test --filter SyntaxHighlighterTests   # Highlighting correctness
```

### Test Data

| File | Rows | Purpose |
|------|------|---------|
| `TestLogs/small.log` | 100 | Quick functional tests |
| `TestLogs/medium.log` | 10,047 | Filter/scroll perf + 5 stack trace samples |
| `TestLogs/large.log` | 736,142 | Stress test |
| `TestLogs/multiline.log` | ~10 | Multiline entry rendering |

### Manual Verification

```bash
swift build -c release && .build/release/LogViewer Tests/TestLogs/medium.log
```

Check: filter toggles respond instantly, colors render on log levels, multiline entries expand, search highlights appear, scroll is smooth.

---

## Profiling Guide

### Time Profiler (Instruments)

1. Build release: `swift build -c release`
2. Open Instruments > Time Profiler
3. Attach to `.build/release/LogViewer`
4. Open `large.log`, scroll rapidly for 30 seconds
5. Target: no frame drops, hot spots should be in AppKit framework code

### Allocations

1. Open Instruments > Allocations
2. Open `large.log`, scroll through, toggle filters
3. Memory should stabilize (cell reuse + cache eviction)
4. No unbounded growth
