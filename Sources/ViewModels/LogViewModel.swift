//
//  LogViewModel.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import Foundation
import Observation

/// Main view model for the log viewer application
@Observable
@MainActor
final class LogViewModel {
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

    // MARK: - Private Properties

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

    /// File watcher for auto-refresh
    private let fileWatcher = FileWatcher()

    /// Auto-refresh timer
    private var autoRefreshTimer: Timer? = nil

    // MARK: - Initialization

    init() {
        // Initialize with empty state
    }

    // MARK: - Public Methods

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
                throw LogViewerError.invalidFile
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

    /// Apply current filters to populate displayedEntries
    func applyFilters() {
        // Cancel any in-flight filter task
        filterTask?.cancel()

        // For large datasets, run filtering in background
        if allEntries.count > backgroundTaskThreshold {
            filterTask = Task {
                let filtered = await performFiltering()
                if !Task.isCancelled {
                    await MainActor.run {
                        self.displayedEntries = filtered
                        print("🎯 Filters applied (async): \(filtered.count) entries displayed (from \(self.allEntries.count) total)")
                        // Update search matches if in jump mode
                        if self.searchState.mode == .jumpToMatch && !self.searchState.query.isEmpty {
                            self.updateSearchMatchesInBackground()
                        }
                    }
                }
            }
        } else {
            // For small datasets, filter synchronously
            displayedEntries = performFilteringSynchronous()
            print("🎯 Filters applied: \(displayedEntries.count) entries displayed (from \(allEntries.count) total)")
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

    /// Perform filtering on background thread (async)
    private func performFiltering() async -> [LogEntry] {
        let entries = allEntries
        let levels = filterState.enabledLevels
        let startTime = filterState.timeRangeStart
        let endTime = filterState.timeRangeEnd
        let query = searchState.query
        let mode = searchState.mode
        let caseSensitive = searchState.isCaseSensitive

        return await Task.detached {
            var filtered = entries

            // Apply log level filter
            filtered = filtered.filter { entry in
                // Entries with nil level are always shown
                guard let level = entry.level else { return true }
                return levels.contains(level)
            }

            // Apply time range filter
            if let startTime = startTime {
                filtered = filtered.filter { entry in
                    // Entries with nil timestamp shown by default
                    guard let timestamp = entry.timestamp else { return true }
                    return timestamp >= startTime
                }
            }

            if let endTime = endTime {
                filtered = filtered.filter { entry in
                    // Entries with nil timestamp shown by default
                    guard let timestamp = entry.timestamp else { return true }
                    return timestamp <= endTime
                }
            }

            // Apply search filter
            if !query.isEmpty {
                let regex = try? self.createSearchRegex(query: query, caseSensitive: caseSensitive)

                if mode == .filterToMatch {
                    // Filter mode: exclude non-matching entries
                    filtered = filtered.filter { entry in
                        self.entryMatches(entry, regex: regex)
                    }
                }
                // Note: Jump mode matching is handled separately in updateSearchMatches()
            }

            return filtered
        }.value
    }

    /// Perform filtering synchronously (main thread)
    private func performFilteringSynchronous() -> [LogEntry] {
        var filtered = allEntries

        // Apply log level filter
        filtered = filtered.filter { entry in
            // Entries with nil level are always shown
            guard let level = entry.level else { return true }
            return filterState.enabledLevels.contains(level)
        }

        // Apply time range filter
        if let startTime = filterState.timeRangeStart {
            filtered = filtered.filter { entry in
                // Entries with nil timestamp shown by default
                guard let timestamp = entry.timestamp else { return true }
                return timestamp >= startTime
            }
        }

        if let endTime = filterState.timeRangeEnd {
            filtered = filtered.filter { entry in
                // Entries with nil timestamp shown by default
                guard let timestamp = entry.timestamp else { return true }
                return timestamp <= endTime
            }
        }

        // Apply search filter
        if !searchState.query.isEmpty {
            let regex = try? createSearchRegex(query: searchState.query, caseSensitive: searchState.isCaseSensitive)

            if searchState.mode == .filterToMatch {
                // Filter mode: exclude non-matching entries
                filtered = filtered.filter { entry in
                    entryMatches(entry, regex: regex)
                }
            }
            // Note: Jump mode matching is handled in performSearchInBackground()
        }

        return filtered
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
        partialLineBuffer = nil
        hasNewContent = false
        errorMessage = nil
    }

    /// Update auto-refresh settings (called when settings change)
    func updateAutoRefreshSettings() {
        if settingsState.autoRefreshEnabled {
            startAutoRefreshTimer()
        } else {
            stopAutoRefreshTimer()
        }
    }
}

// MARK: - Error Types

enum LogViewerError: Error {
    case invalidFile
    case fileTooLarge
    case binaryFile
    case permissionDenied
    case fileNotFound
}
