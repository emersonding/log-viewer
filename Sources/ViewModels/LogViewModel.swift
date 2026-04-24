//
//  LogViewModel.swift
//  Lumen
//
//  Created on 2026-04-13.
//

import Foundation
import Observation

// MARK: - Sort Order

enum TimestampSortOrder {
    case original   // file order
    case ascending  // oldest first
    case descending // newest first
}

/// Main view model for the log viewer application
@Observable
@MainActor
final class LogViewModel {
    static let maxExtractedFields = 16

    // MARK: - Published Properties

    /// All parsed log entries from the file
    var allEntries: [LogEntry] = []

    /// Filtered and/or searched entries to display
    var displayedEntries: [LogEntry] = []

    /// Current filter state
    var filterState: FilterState = FilterState()

    /// Current search state
    var searchState: SearchState = SearchState()

    /// Application settings
    var settingsState: SettingsState = .default

    /// Loading state indicator
    var isLoading: Bool = false

    /// Parse/index progress (0.0 to 1.0) for UI progress indicator
    var loadingProgress: Double = 0.0

    /// Error message to display to user
    var errorMessage: String? = nil

    /// Current open file URL
    var currentFileURL: URL? = nil

    /// Current byte offset in file (for incremental refresh)
    var currentFileOffset: Int? = nil

    /// Flag indicating new content is available (for UI indicator)
    var hasNewContent: Bool = false

    /// User scroll position at bottom (for auto-scroll decision)
    var isScrolledToBottom: Bool = true

    /// Current sort order for timestamp column
    var timestampSortOrder: TimestampSortOrder = .original

    /// Counter that increments on each applyFilters() call.
    /// Used by AppKitLogTableView to detect when to reload data.
    var filterChangeCounter: Int = 0

    /// All currently opened files (tabs)
    var openedFiles: [OpenedFile] = []

    /// History of previously opened files
    var fileHistory: [OpenedFile] = []

    /// Whether the sidebar/history panel is visible
    var isSidebarVisible: Bool = true

    /// User-selected key=value fields to show as table columns.
    var extractedFieldNames: [String] = []

    /// Counter that increments when extracted field columns change.
    var fieldChangeCounter: Int = 0

    // MARK: - Private Properties

    private let maxHistoryCount = 50
    private let historyKey = "fileHistoryPaths"
    private let sidebarVisibleKey = "isSidebarVisible"

    private let parser = LogParser()
    private let fileSizeWarningThreshold: Int64 = 1_000_000_000 // 1GB
    private let fileSizeMaxThreshold: Int64 = 2_000_000_000 // 2GB
    private let memoryMappingThreshold: Int64 = 10_000_000 // 10MB
    private let backgroundTaskThreshold = 10_000 // Run filters in background for >10k entries

    /// Line index for O(1) line access by byte offset
    private var lineIndex = LineIndex()

    /// Buffer for incomplete last line during refresh
    private var partialLineBuffer: String? = nil

    /// Current filter task (for cancellation)
    private var filterTask: Task<Void, Never>? = nil

    /// Current search task (for cancellation)
    private var searchTask: Task<Void, Never>? = nil

    /// Debounce delay for filter application (ms)
    private let filterDebounceNs: UInt64 = 50_000_000 // 50ms

    /// File watcher for auto-refresh
    private let fileWatcher = FileWatcher()

    /// Auto-refresh timer
    private var autoRefreshTimer: Timer? = nil

    /// Cached field regexes keyed by exact field name.
    private var fieldRegexCache: [String: NSRegularExpression] = [:]

    // MARK: - Initialization

    init() {
        loadHistory()
        isSidebarVisible = UserDefaults.standard.object(forKey: sidebarVisibleKey) as? Bool ?? true
    }

    // MARK: - Public Methods

    /// Add a field column extracted lazily from each entry's message.
    func addExtractedField(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidExtractedFieldName(name),
              extractedFieldNames.count < Self.maxExtractedFields,
              !extractedFieldNames.contains(name) else {
            return
        }

        extractedFieldNames.append(name)
        fieldChangeCounter += 1
    }

    /// Remove a previously added extracted field column.
    func removeExtractedField(_ name: String) {
        let oldCount = extractedFieldNames.count
        extractedFieldNames.removeAll { $0 == name }
        if extractedFieldNames.count != oldCount {
            fieldChangeCounter += 1
        }
    }

    /// Validate common logfmt-style field names.
    func isValidExtractedFieldName(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return name.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil
    }

    /// Extract field=value, field="value", or field='value' from a log entry message.
    func extractedFieldValue(named fieldName: String, in entry: LogEntry) -> String {
        guard let regex = regexForExtractedField(named: fieldName) else { return "" }

        let message = entry.message
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range) else { return "" }

        for groupIndex in 1..<match.numberOfRanges {
            let groupRange = match.range(at: groupIndex)
            guard groupRange.location != NSNotFound,
                  let range = Range(groupRange, in: message) else {
                continue
            }
            return String(message[range])
        }

        return ""
    }

    /// Open and parse a log file
    /// - Parameter url: File URL to open
    func openFile(url: URL) async {
        // Clear error state
        errorMessage = nil

        // Set loading state
        isLoading = true

        do {
            // Check file exists and get attributes
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSize = fileAttributes[.size] as? Int64 else {
                throw LumenError.invalidFile
            }

            // Check file size constraints
            if fileSize > fileSizeMaxThreshold {
                let sizeGB = Double(fileSize) / 1_000_000_000.0
                errorMessage = String(format: "File is too large (%.2f GB). Maximum supported size is 2 GB.", sizeGB)
                isLoading = false
                return
            }

            // TODO: Show warning dialog for files > 1GB (requires UI interaction)
            // For now, we'll just proceed with a console warning
            if fileSize > fileSizeWarningThreshold {
                let sizeGB = Double(fileSize) / 1_000_000_000.0
                print("Warning: Opening large file (%.2f GB). This may be slow.", sizeGB)
            }

            // Read file data
            let data: Data
            if fileSize > memoryMappingThreshold {
                // Use memory-mapped I/O for large files
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } else {
                // Read normally for small files
                data = try Data(contentsOf: url)
            }

            // Binary file detection: check first 8KB for null bytes
            let sampleSize = min(8192, data.count)
            let sampleData = data.prefix(sampleSize)
            if sampleData.contains(0x00) {
                errorMessage = "This appears to be a binary file. Only text log files are supported."
                isLoading = false
                return
            }

            // Clear existing data
            allEntries = []
            displayedEntries = []
            currentFileURL = nil
            currentFileOffset = nil
            partialLineBuffer = nil
            hasNewContent = false
            loadingProgress = 0.0
            lineIndex = LineIndex()

            // Build line index for O(1) line access (progress: first 30%)
            let vm = self
            lineIndex = await LineIndex.build(from: data) { fraction in
                Task { @MainActor in
                    vm.loadingProgress = fraction * 0.3
                }
            }

            // Parse the file with progress callback (progress: remaining 70%)
            let entries = await parser.parse(data) { fraction in
                Task { @MainActor in
                    vm.loadingProgress = 0.3 + fraction * 0.7
                }
            }

            // Update state
            allEntries = entries
            currentFileURL = url
            currentFileOffset = data.count
            loadingProgress = 1.0

            // Debug logging
            print("✅ File opened successfully: \(url.lastPathComponent)")
            print("📊 Total entries parsed: \(entries.count)")
            print("🔍 First 3 entries:")
            for (index, entry) in entries.prefix(3).enumerated() {
                print("  Entry \(index): level=\(entry.level?.rawValue ?? "nil"), text=\(entry.rawLine.prefix(50))...")
            }

            // Apply current filters
            applyFilters()

            // Track opened file and history
            let openedFile = OpenedFile(url: url)
            if !openedFiles.contains(where: { $0.url == url }) {
                openedFiles.append(openedFile)
            }
            addToHistory(openedFile)

            // Start file watching for auto-refresh
            startFileWatching()

        } catch let error as NSError {
            // Handle specific error types
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileReadNoSuchFileError:
                    errorMessage = "File not found: \(url.lastPathComponent)"
                case NSFileReadNoPermissionError:
                    errorMessage = "Permission denied: Cannot read \(url.lastPathComponent)"
                default:
                    errorMessage = "Failed to open file: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Failed to open file: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Failed to open file: \(error.localizedDescription)"
        }

        // Clear loading state
        isLoading = false
    }

    /// Apply current filters to populate displayedEntries.
    /// For large datasets, debounces rapid calls (e.g. toggling multiple filters quickly)
    /// and runs filtering on a background thread.
    func applyFilters() {
        // Cancel any in-flight filter task
        filterTask?.cancel()

        // For large datasets, debounce + run in background
        if allEntries.count > backgroundTaskThreshold {
            filterTask = Task {
                // Debounce: wait briefly so rapid toggles coalesce into one filter pass
                try? await Task.sleep(nanoseconds: filterDebounceNs)
                guard !Task.isCancelled else { return }

                var filtered = await performFiltering()
                if !Task.isCancelled {
                    if self.timestampSortOrder != .original {
                        filtered = self.sortByTimestamp(filtered, ascending: self.timestampSortOrder == .ascending)
                    }
                    self.displayedEntries = filtered
                    self.filterChangeCounter += 1
                    // Update search matches if in jump mode
                    if self.searchState.mode == .jumpToMatch && !self.searchState.query.isEmpty {
                        self.updateSearchMatchesInBackground()
                    }
                }
            }
        } else {
            // For small datasets, filter synchronously
            var filtered = performFilteringSynchronous()
            if timestampSortOrder != .original {
                filtered = sortByTimestamp(filtered, ascending: timestampSortOrder == .ascending)
            }
            displayedEntries = filtered
            filterChangeCounter += 1
            // Update search matches for jump mode
            if searchState.mode == .jumpToMatch && !searchState.query.isEmpty {
                let regex = try? createSearchRegex(query: searchState.query, caseSensitive: searchState.isCaseSensitive)
                updateSearchMatches(in: displayedEntries, regex: regex)
            } else if searchState.query.isEmpty {
                searchState.matchingLineIDs = []
                searchState.currentMatchIndex = 0
            }
        }
    }

    /// Update search matches in the background for jump mode
    private func updateSearchMatchesInBackground() {
        // Cancel any in-flight search task
        searchTask?.cancel()

        let query = searchState.query
        let caseSensitive = searchState.isCaseSensitive
        let entries = displayedEntries

        searchTask = Task {
            let regex = try? self.createSearchRegex(query: query, caseSensitive: caseSensitive)
            let matchingIDs = entries.compactMap { entry -> UUID? in
                self.entryMatches(entry, regex: regex) ? entry.id : nil
            }

            if !Task.isCancelled {
                await MainActor.run {
                    self.searchState.matchingLineIDs = matchingIDs
                    self.searchState.currentMatchIndex = matchingIDs.isEmpty ? 0 : 0
                }
            }
        }
    }

    /// Perform filtering on background thread (async).
    /// Applies all three filter dimensions in a single pass for efficiency.
    private func performFiltering() async -> [LogEntry] {
        let entries = allEntries
        let levels = filterState.enabledLevels
        let startTime = filterState.timeRangeStart
        let endTime = filterState.timeRangeEnd
        let query = searchState.query
        let mode = searchState.mode
        let caseSensitive = searchState.isCaseSensitive

        return await Task.detached {
            let regex: NSRegularExpression? = (!query.isEmpty && mode == .filterToMatch)
                ? (try? self.createSearchRegex(query: query, caseSensitive: caseSensitive))
                : nil

            // Single-pass filter: evaluate all conditions per entry instead of
            // chaining multiple .filter() calls that create intermediate arrays.
            return entries.filter { entry in
                // Log level filter
                if let level = entry.level, !levels.contains(level) {
                    return false
                }
                // Time range filter
                if let startTime = startTime, let ts = entry.timestamp, ts < startTime {
                    return false
                }
                if let endTime = endTime, let ts = entry.timestamp, ts > endTime {
                    return false
                }
                // Search filter (only in filterToMatch mode)
                if let regex = regex {
                    return self.entryMatches(entry, regex: regex)
                }
                return true
            }
        }.value
    }

    /// Perform filtering synchronously (main thread).
    /// Single-pass filter for efficiency — no intermediate arrays.
    private func performFilteringSynchronous() -> [LogEntry] {
        let levels = filterState.enabledLevels
        let startTime = filterState.timeRangeStart
        let endTime = filterState.timeRangeEnd
        let regex: NSRegularExpression? = (!searchState.query.isEmpty && searchState.mode == .filterToMatch)
            ? (try? createSearchRegex(query: searchState.query, caseSensitive: searchState.isCaseSensitive))
            : nil

        return allEntries.filter { entry in
            if let level = entry.level, !levels.contains(level) {
                return false
            }
            if let startTime = startTime, let ts = entry.timestamp, ts < startTime {
                return false
            }
            if let endTime = endTime, let ts = entry.timestamp, ts > endTime {
                return false
            }
            if let regex = regex {
                return entryMatches(entry, regex: regex)
            }
            return true
        }
    }

    /// Create a search regex with escaped pattern for plain-text search
    private nonisolated func createSearchRegex(query: String, caseSensitive: Bool) throws -> NSRegularExpression {
        // Escape special regex characters for plain-text search (SR-11)
        let escapedPattern = NSRegularExpression.escapedPattern(for: query)

        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        return try NSRegularExpression(pattern: escapedPattern, options: options)
    }

    /// Check if an entry matches the search regex
    private nonisolated func entryMatches(_ entry: LogEntry, regex: NSRegularExpression?) -> Bool {
        guard let regex = regex else { return false }

        let range = NSRange(entry.rawLine.startIndex..., in: entry.rawLine)
        return regex.firstMatch(in: entry.rawLine, range: range) != nil
    }

    /// Update search state with matching line IDs for jump mode
    private func updateSearchMatches(in entries: [LogEntry], regex: NSRegularExpression?) {
        guard let regex = regex else {
            searchState.matchingLineIDs = []
            searchState.currentMatchIndex = 0
            return
        }

        // Find all entries that match the search query
        let matchingIDs = entries.compactMap { entry -> UUID? in
            entryMatches(entry, regex: regex) ? entry.id : nil
        }

        searchState.matchingLineIDs = matchingIDs
        // Reset to first match when updating search
        searchState.currentMatchIndex = matchingIDs.isEmpty ? 0 : 0
    }

    /// Navigate to the next search match
    func nextMatch() {
        guard searchState.hasMatches else { return }

        searchState.currentMatchIndex = (searchState.currentMatchIndex + 1) % searchState.matchCount
    }

    /// Navigate to the previous search match
    func previousMatch() {
        guard searchState.hasMatches else { return }

        if searchState.currentMatchIndex == 0 {
            searchState.currentMatchIndex = searchState.matchCount - 1
        } else {
            searchState.currentMatchIndex -= 1
        }
    }

    /// Get the current match ID for scrolling
    var currentMatchID: UUID? {
        guard searchState.hasMatches,
              searchState.currentMatchIndex < searchState.matchingLineIDs.count else {
            return nil
        }
        return searchState.matchingLineIDs[searchState.currentMatchIndex]
    }

    /// Refresh the log file by reading new content incrementally
    func refresh() async {
        // Guard: Must have an open file
        guard let fileURL = currentFileURL else {
            return
        }

        guard let currentOffset = currentFileOffset else {
            // No offset stored, do a full re-read
            await openFile(url: fileURL)
            return
        }

        do {
            // Get current file size
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = fileAttributes[.size] as? Int64 else {
                return
            }

            // Check for truncation (file smaller than our offset)
            if fileSize < currentOffset {
                // File was truncated, do full re-read
                await openFile(url: fileURL)
                return
            }

            // Check if there's new data
            if fileSize == currentOffset {
                // No new data, nothing to do
                return
            }

            // Read only the new bytes
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            // Seek to our stored offset
            try fileHandle.seek(toOffset: UInt64(currentOffset))

            // Read new data
            let newData = fileHandle.readDataToEndOfFile()

            guard !newData.isEmpty else {
                return
            }

            // Convert to string (handle invalid UTF-8)
            var newContent = String(data: newData, encoding: .utf8) ?? String(decoding: newData, as: UTF8.self)

            // Prepend partial line buffer from previous refresh if it exists
            if let bufferedLine = partialLineBuffer {
                newContent = bufferedLine + newContent
                partialLineBuffer = nil
            }

            // Check if the last line is incomplete (no newline terminator)
            let endsWithNewline = newContent.hasSuffix("\n") || newContent.hasSuffix("\r\n") || newContent.hasSuffix("\r")

            if !endsWithNewline && !newContent.isEmpty {
                // Buffer the incomplete last line
                if let lastNewlineIndex = newContent.lastIndex(where: { $0 == "\n" || $0 == "\r" }) {
                    // Extract everything after the last newline
                    let nextIndex = newContent.index(after: lastNewlineIndex)
                    partialLineBuffer = String(newContent[nextIndex...])
                    // Keep only the complete lines for parsing
                    newContent = String(newContent[...lastNewlineIndex])
                } else {
                    // Entire content is one incomplete line
                    partialLineBuffer = newContent
                    newContent = ""
                }
            }

            // Parse new entries if we have complete lines
            if !newContent.isEmpty {
                let newData = newContent.data(using: .utf8) ?? Data()
                let newEntries = await parser.parse(newData)

                // Adjust line numbers to continue from last entry
                let lastLineNumber = allEntries.last?.lineNumber ?? 0
                let adjustedEntries = newEntries.enumerated().map { index, entry in
                    LogEntry(
                        id: entry.id,
                        lineNumber: lastLineNumber + index + 1,
                        timestamp: entry.timestamp,
                        level: entry.level,
                        message: entry.message,
                        rawLine: entry.rawLine
                    )
                }

                // Append new entries
                allEntries.append(contentsOf: adjustedEntries)

                // Update file offset (only count what we actually parsed, not buffered partial line)
                currentFileOffset = Int(fileSize) - (partialLineBuffer?.utf8.count ?? 0)

                // Re-apply filters to full dataset
                applyFilters()

                // Set new content flag if user is not at bottom
                if !isScrolledToBottom {
                    hasNewContent = true
                }
                // If user is at bottom, UI should auto-scroll (handled by view layer)
            }

        } catch let error as NSError {
            // Handle errors gracefully
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileReadNoSuchFileError:
                    errorMessage = "File was deleted: \(fileURL.lastPathComponent)"
                case NSFileReadNoPermissionError:
                    errorMessage = "Permission denied: Cannot read \(fileURL.lastPathComponent)"
                default:
                    errorMessage = "Failed to refresh file: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Failed to refresh file: \(error.localizedDescription)"
            }
        }
    }

    /// Start file watching for auto-refresh
    private func startFileWatching() {
        guard let fileURL = currentFileURL else { return }

        // Stop any existing watching
        stopFileWatching()

        // Start watching the file
        fileWatcher.start(path: fileURL.path) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Only auto-refresh if enabled in settings
                if self.settingsState.autoRefreshEnabled {
                    await self.refresh()
                }
            }
        }

        // Start timer-based refresh if auto-refresh is enabled
        startAutoRefreshTimer()
    }

    /// Stop file watching
    private func stopFileWatching() {
        fileWatcher.stop()
        stopAutoRefreshTimer()
    }

    /// Start timer-based auto-refresh
    private func startAutoRefreshTimer() {
        // Stop any existing timer
        stopAutoRefreshTimer()

        // Only start timer if auto-refresh is enabled
        guard settingsState.autoRefreshEnabled else { return }

        let interval = settingsState.autoRefreshInterval
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    /// Stop auto-refresh timer
    private func stopAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    /// Close the current file and stop watching
    func closeFile() {
        stopFileWatching()
        currentFileURL = nil
        currentFileOffset = nil
        allEntries = []
        displayedEntries = []
        extractedFieldNames = []
        fieldChangeCounter += 1
        partialLineBuffer = nil
        hasNewContent = false
        errorMessage = nil
    }

    // MARK: - Opened Files & History

    /// Close an opened file tab
    func closeOpenedFile(_ file: OpenedFile) {
        openedFiles.removeAll { $0.url == file.url }
        if currentFileURL == file.url {
            if let next = openedFiles.first {
                Task { await openFile(url: next.url) }
            } else {
                closeFile()
            }
        }
    }

    /// Switch to a previously opened file
    func switchToFile(_ file: OpenedFile) async {
        await openFile(url: file.url)
    }

    /// Toggle sidebar visibility
    func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible)
    }

    /// Set sidebar visibility explicitly
    func setSidebarVisible(_ visible: Bool) {
        isSidebarVisible = visible
        UserDefaults.standard.set(visible, forKey: sidebarVisibleKey)
    }

    /// Remove a single entry from history
    func removeFromHistory(_ file: OpenedFile) {
        fileHistory.removeAll { $0.url == file.url }
        saveHistory()
    }

    /// Clear all history
    func clearHistory() {
        fileHistory.removeAll()
        saveHistory()
    }

    /// Add a file to the top of history, deduplicating by URL
    private func addToHistory(_ file: OpenedFile) {
        fileHistory.removeAll { $0.url == file.url }
        fileHistory.insert(file, at: 0)
        if fileHistory.count > maxHistoryCount {
            fileHistory = Array(fileHistory.prefix(maxHistoryCount))
        }
        saveHistory()
    }

    /// Persist history paths to UserDefaults
    private func saveHistory() {
        let paths = fileHistory.map { $0.url.path }
        UserDefaults.standard.set(paths, forKey: historyKey)
    }

    /// Load history from UserDefaults
    private func loadHistory() {
        guard let paths = UserDefaults.standard.stringArray(forKey: historyKey) else { return }
        fileHistory = paths.map { OpenedFile(url: URL(fileURLWithPath: $0)) }
    }

    /// Update auto-refresh settings (called when settings change)
    func updateAutoRefreshSettings() {
        if settingsState.autoRefreshEnabled {
            startAutoRefreshTimer()
        } else {
            stopAutoRefreshTimer()
        }
    }

    /// Toggle timestamp sort order and re-apply filters
    func toggleTimestampSort() {
        switch timestampSortOrder {
        case .original:
            timestampSortOrder = .ascending
        case .ascending:
            timestampSortOrder = .descending
        case .descending:
            timestampSortOrder = .original
        }
        applyFilters()
    }

    /// Sort entries by timestamp, keeping nil-timestamp entries grouped with
    /// their nearest preceding timestamped entry (ELK-style).
    private func sortByTimestamp(_ entries: [LogEntry], ascending: Bool) -> [LogEntry] {
        // Group entries into blocks: each block starts with a timestamped entry
        // followed by zero or more nil-timestamp continuation entries.
        var blocks: [(timestamp: Date?, entries: [LogEntry])] = []
        var currentBlock: [LogEntry] = []
        var currentTimestamp: Date? = nil

        for entry in entries {
            if entry.timestamp != nil {
                // Flush previous block
                if !currentBlock.isEmpty {
                    blocks.append((timestamp: currentTimestamp, entries: currentBlock))
                }
                currentBlock = [entry]
                currentTimestamp = entry.timestamp
            } else {
                // Continuation line — stays with current block
                currentBlock.append(entry)
            }
        }
        // Flush last block
        if !currentBlock.isEmpty {
            blocks.append((timestamp: currentTimestamp, entries: currentBlock))
        }

        // Sort blocks by timestamp; nil-timestamp blocks go to the end
        let sorted = blocks.sorted { a, b in
            guard let ta = a.timestamp else { return false }
            guard let tb = b.timestamp else { return true }
            return ascending ? ta < tb : ta > tb
        }

        return sorted.flatMap { $0.entries }
    }

    private func regexForExtractedField(named fieldName: String) -> NSRegularExpression? {
        if let cached = fieldRegexCache[fieldName] {
            return cached
        }

        guard isValidExtractedFieldName(fieldName) else { return nil }

        let escapedName = NSRegularExpression.escapedPattern(for: fieldName)
        let pattern = #"(?:^|[\s,\[{(])"# + escapedName + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,\]})]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        fieldRegexCache[fieldName] = regex
        return regex
    }
}

// MARK: - Error Types

enum LumenError: Error {
    case invalidFile
    case fileTooLarge
    case binaryFile
    case permissionDenied
    case fileNotFound
}
