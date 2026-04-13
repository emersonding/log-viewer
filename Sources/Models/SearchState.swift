//
//  SearchState.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import Foundation

/// Search behavior mode
enum SearchMode: String, Codable, Sendable {
    case jumpToMatch = "Jump to Match"
    case filterToMatch = "Filter to Matches"
}

/// State for search functionality
struct SearchState: Sendable {
    var query: String
    var mode: SearchMode
    var isCaseSensitive: Bool
    /// Ordered list of matching IDs (for next/previous navigation)
    var matchingLineIDs: [UUID] {
        didSet { _matchingLineIDSet = Set(matchingLineIDs) }
    }
    /// Set for O(1) membership checks (kept in sync with matchingLineIDs)
    private(set) var _matchingLineIDSet: Set<UUID> = []
    var currentMatchIndex: Int

    init(
        query: String = "",
        mode: SearchMode = .jumpToMatch,
        isCaseSensitive: Bool = false,
        matchingLineIDs: [UUID] = [],
        currentMatchIndex: Int = 0
    ) {
        self.query = query
        self.mode = mode
        self.isCaseSensitive = isCaseSensitive
        self.matchingLineIDs = matchingLineIDs
        self._matchingLineIDSet = Set(matchingLineIDs)
        self.currentMatchIndex = currentMatchIndex
    }

    /// Returns true if there are active search results
    var hasMatches: Bool {
        return !matchingLineIDs.isEmpty
    }

    /// Returns the total number of matches
    var matchCount: Int {
        return matchingLineIDs.count
    }

    /// O(1) check if an ID is a search match
    func isMatch(_ id: UUID) -> Bool {
        return _matchingLineIDSet.contains(id)
    }
}
