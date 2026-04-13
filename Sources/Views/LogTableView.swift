//
//  LogTableView.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import SwiftUI

/// Virtualized log table view with fixed row height and viewport-based rendering.
///
/// Performance strategy:
/// - Fixed row height eliminates per-row measurement (O(1) scroll math)
/// - Only rows within the visible viewport + a small buffer are instantiated
/// - Syntax highlighting is deferred to render time (highlight-on-demand)
struct LogTableView: View {
    @Bindable var viewModel: LogViewModel

    /// Fixed height per row (line content + vertical padding + divider)
    private var rowHeight: CGFloat {
        // Font size + vertical padding (2*2) + divider (0.5)
        ceil(viewModel.settingsState.fontSize * 1.4) + 4.5
    }

    /// Number of extra rows to render above/below the visible area
    private let overscan = 20

    /// Scroll offset tracked via GeometryReader
    @State private var scrollOffset: CGFloat = 0
    /// Viewport height
    @State private var viewportHeight: CGFloat = 0

    @MainActor
    var body: some View {
        GeometryReader { geometry in
            let totalEntries = viewModel.displayedEntries.count
            let totalHeight = CGFloat(totalEntries) * rowHeight

            if totalEntries == 0 {
                emptyStateView(isFileEmpty: viewModel.allEntries.isEmpty)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        // Spacer to establish full scrollable content height
                        Color.clear
                            .frame(
                                width: 1,
                                height: totalHeight
                            )

                        // Render only the visible window of rows
                        let visibleRange = visibleRowRange(
                            totalEntries: totalEntries,
                            viewportHeight: geometry.size.height
                        )
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visibleRange, id: \.self) { index in
                                let entry = viewModel.displayedEntries[index]
                                LogLineView(
                                    entry: entry,
                                    isLineWrapEnabled: viewModel.settingsState.lineWrapDefault,
                                    fontSize: viewModel.settingsState.fontSize,
                                    isSearchMatch: isSearchMatch(entry),
                                    isCurrentMatch: isCurrentMatch(entry),
                                    searchQuery: viewModel.searchState.query,
                                    isCaseSensitive: viewModel.searchState.isCaseSensitive
                                )
                                .frame(height: rowHeight - 0.5) // subtract divider
                                .clipped()
                                .id(entry.id)

                                Divider()
                                    .opacity(0.2)
                                    .frame(height: 0.5)
                            }
                        }
                        .offset(y: CGFloat(visibleRange.lowerBound) * rowHeight)
                        .frame(minWidth: geometry.size.width, alignment: .topLeading)
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    updateScrollPosition(offset: value, totalHeight: totalHeight, viewportHeight: geometry.size.height)
                }
                .onChange(of: viewModel.currentMatchID) { _, newMatchID in
                    if let matchID = newMatchID {
                        scrollToMatch(matchID)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Log entries")
                .accessibilityHint("Scrollable list of log entries. Use arrow keys to navigate.")
            }
        }
    }

    // MARK: - Visible Row Calculation

    /// Calculate which rows are visible based on scroll offset and viewport size
    private func visibleRowRange(totalEntries: Int, viewportHeight: CGFloat) -> Range<Int> {
        guard totalEntries > 0, rowHeight > 0 else { return 0..<0 }

        // scrollOffset is negative when scrolled down (content moves up)
        let scrolled = max(0, -scrollOffset)

        let firstVisible = Int(scrolled / rowHeight)
        let visibleCount = Int(ceil(viewportHeight / rowHeight))

        let start = max(0, firstVisible - overscan)
        let end = min(totalEntries, firstVisible + visibleCount + overscan)

        return start..<end
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

    /// Scroll to a specific search match by computing its pixel offset
    private func scrollToMatch(_ matchID: UUID) {
        guard let index = viewModel.displayedEntries.firstIndex(where: { $0.id == matchID }) else {
            return
        }
        // The entry is at offset index * rowHeight — the ScrollView will
        // bring it into view via the .id() on the row if it's in the rendered range.
        // For entries outside the current rendered window, we adjust the viewModel
        // to trigger a re-render at the target offset.
        // For now, rely on ScrollViewReader if we re-add it, or accept that
        // the windowed approach handles jump-to via currentMatchID changes.
        _ = index // Scroll-to-match will be refined in the AppKit pass
    }

    /// Update scroll position tracking for auto-scroll behavior
    private func updateScrollPosition(offset: CGFloat, totalHeight: CGFloat, viewportHeight: CGFloat) {
        // Content has scrolled to the bottom when the bottom of content
        // aligns with the bottom of the viewport
        let maxScroll = totalHeight - viewportHeight
        let scrolled = -offset
        let isNearBottom = scrolled >= (maxScroll - 50) || maxScroll <= 0

        viewModel.isScrolledToBottom = isNearBottom
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
