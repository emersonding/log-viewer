//
//  SearchBar.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import SwiftUI

/// Search bar view with text field, match counter, and mode indicator
@MainActor
struct SearchBar: View {
    // MARK: - Environment

    @Environment(LogViewModel.self) var viewModel

    // MARK: - Bindings

    @Binding var shouldBeFocused: Bool

    // MARK: - State

    @State private var localQuery: String = ""
    @FocusState private var isSearchFocused: Bool

    // MARK: - Initialization

    init(shouldBeFocused: Binding<Bool> = .constant(false)) {
        self._shouldBeFocused = shouldBeFocused
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            // Text field
            TextField("Search logs...", text: $localQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onChange(of: localQuery) { _, newValue in
                    viewModel.searchState.query = newValue
                    viewModel.applyFilters()
                }
                .onSubmit {
                    // Enter key: next match in jump mode
                    if viewModel.searchState.mode == .jumpToMatch
                        && !viewModel.searchState.query.isEmpty
                    {
                        viewModel.nextMatch()
                    }
                }
                .onExitCommand {
                    // Esc key: de-focus search field
                    isSearchFocused = false
                }
                .accessibilityLabel("Search logs")
                .accessibilityHint("Enter text to search log entries")
                .accessibilityValue(viewModel.searchState.query.isEmpty ? "Empty" : viewModel.searchState.query)

            // Match count label
            if !viewModel.searchState.query.isEmpty {
                matchCountLabel
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .accessibilityLabel(matchCountAccessibilityLabel)
            }

            // Case-sensitive toggle button (icon: Aa)
            Button(action: {
                viewModel.searchState.isCaseSensitive.toggle()
                // Re-trigger search with new case sensitivity
                if !viewModel.searchState.query.isEmpty {
                    viewModel.applyFilters()
                }
            }) {
                Text("Aa")
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .background(
                        viewModel.searchState.isCaseSensitive
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear
                    )
                    .cornerRadius(4)
            }
            .help("Toggle case-sensitive search (Aa)")
            .accessibilityLabel("Case sensitive")
            .accessibilityValue(
                viewModel.searchState.isCaseSensitive ? "On" : "Off"
            )

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            // Sync local query with viewModel state
            localQuery = viewModel.searchState.query
            // Set up global Cmd+F keyboard shortcut
            setupGlobalSearchShortcut()
        }
        .onChange(of: viewModel.searchState.query) { _, newValue in
            // Keep localQuery in sync if changed from elsewhere
            if localQuery != newValue {
                localQuery = newValue
            }
        }
        .onChange(of: shouldBeFocused) { _, newValue in
            // Focus search field when Cmd+F is pressed
            if newValue {
                isSearchFocused = true
                shouldBeFocused = false
            }
        }
    }

    // MARK: - Private Views

    private var matchCountLabel: some View {
        Group {
            if viewModel.searchState.mode == .jumpToMatch {
                // Jump mode: "3 of 42"
                if viewModel.searchState.hasMatches {
                    Text(
                        "\(viewModel.searchState.currentMatchIndex + 1) of \(viewModel.searchState.matchCount)"
                    )
                } else {
                    Text("No matches")
                        .foregroundColor(.red)
                }
            } else {
                // Filter mode: "42 matches"
                if viewModel.searchState.matchCount > 0 {
                    Text("\(viewModel.searchState.matchCount) matches")
                } else {
                    Text("No matches")
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func setupGlobalSearchShortcut() {
        // Set up Cmd+F to focus search field
        // This will be handled by registering with NSApplication in the app delegate
        // or through the ContentView commands
    }

    /// Accessibility label for match count
    private var matchCountAccessibilityLabel: String {
        if viewModel.searchState.mode == .jumpToMatch {
            if viewModel.searchState.hasMatches {
                return "Match \(viewModel.searchState.currentMatchIndex + 1) of \(viewModel.searchState.matchCount)"
            } else {
                return "No matches found"
            }
        } else {
            if viewModel.searchState.matchCount > 0 {
                return "\(viewModel.searchState.matchCount) matches found"
            } else {
                return "No matches found"
            }
        }
    }
}
