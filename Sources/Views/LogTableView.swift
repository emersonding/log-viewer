//
//  LogTableView.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import SwiftUI

/// Virtualized log table view with LazyVStack for performance
struct LogTableView: View {
    @Bindable var viewModel: LogViewModel
    @State private var scrollProxy: ScrollViewProxy?

    @MainActor
    var body: some View {
        GeometryReader { geometry in
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                if viewModel.displayedEntries.isEmpty {
                    // Empty state - check if file is actually empty vs filtered
                    emptyStateView(isFileEmpty: viewModel.allEntries.isEmpty)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.displayedEntries) { entry in
                            LogLineView(
                                entry: entry,
                                isLineWrapEnabled: viewModel.settingsState.lineWrapDefault,
                                fontSize: viewModel.settingsState.fontSize,
                                isSearchMatch: isSearchMatch(entry),
                                isCurrentMatch: isCurrentMatch(entry),
                                searchQuery: viewModel.searchState.query,
                                isCaseSensitive: viewModel.searchState.isCaseSensitive
                            )
                            .id(entry.id)

                            Divider()
                                .opacity(0.2)
                        }
                    }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                updateScrollPosition(offset: value)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: viewModel.currentMatchID) { _, newMatchID in
                if let matchID = newMatchID {
                    scrollToMatch(matchID, proxy: proxy)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Log entries")
            .accessibilityHint("Scrollable list of log entries. Use arrow keys to navigate.")
        }
        }
    }

    // MARK: - Empty State View

    @ViewBuilder
    private func emptyStateView(isFileEmpty: Bool) -> some View {
        let message = isFileEmpty
            ? "File is empty"
            : "No entries match current filters"

        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Empty document icon")

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    // MARK: - Helper Methods

    /// Check if an entry is a search match
    @MainActor
    private func isSearchMatch(_ entry: LogEntry) -> Bool {
        guard viewModel.searchState.mode == .jumpToMatch,
              !viewModel.searchState.query.isEmpty else {
            return false
        }

        return viewModel.searchState.matchingLineIDs.contains(entry.id)
    }

    /// Check if an entry is the current highlighted match
    @MainActor
    private func isCurrentMatch(_ entry: LogEntry) -> Bool {
        guard let currentID = viewModel.currentMatchID else {
            return false
        }

        return entry.id == currentID
    }

    /// Scroll to a specific match
    private func scrollToMatch(_ matchID: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(matchID, anchor: .center)
        }
    }

    /// Update scroll position tracking for auto-scroll behavior
    private func updateScrollPosition(offset: CGFloat) {
        // Track if user is scrolled to bottom
        // Negative offset means scrolled down; close to 0 means at top
        // This is a simplified check - in production, compare with content height
        let isNearBottom = offset > -100 // Within 100 points of bottom

        // Update view model scroll state
        DispatchQueue.main.async {
            viewModel.isScrolledToBottom = isNearBottom
        }
    }
}

// MARK: - Preference Key for Scroll Offset

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

struct LogTableView_Previews: PreviewProvider {
    static var previews: some View {
        LogTableView(viewModel: LogViewModel())
            .frame(width: 800, height: 600)
    }
}
