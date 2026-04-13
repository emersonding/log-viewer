//
//  FilterBar.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import SwiftUI

/// Filter bar containing log level toggles and time range picker
struct FilterBar: View {
    @Bindable var viewModel: LogViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Log level filter section
            HStack(spacing: 8) {
                Text("Levels:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                // Select All / Deselect All buttons
                Button("All") {
                    selectAllLevels()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .help("Enable all log levels")
                .accessibilityLabel("Enable all log levels")
                .accessibilityHint("Shows all log levels in the viewer")

                Button("None") {
                    deselectAllLevels()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .help("Disable all log levels")
                .accessibilityLabel("Disable all log levels")
                .accessibilityHint("Hides all log levels from the viewer")

                Divider()
                    .frame(height: 16)

                // Log level toggle buttons (in severity order)
                ForEach([LogLevel.fatal, .error, .warning, .info, .debug, .trace], id: \.self) { level in
                    LogLevelToggle(
                        level: level,
                        isEnabled: viewModel.filterState.enabledLevels.contains(level)
                    ) { isEnabled in
                        toggleLevel(level, enabled: isEnabled)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Time range filter section
            TimeRangePickerView(
                startDate: Binding(
                    get: { viewModel.filterState.timeRangeStart },
                    set: { newValue in
                        viewModel.filterState.timeRangeStart = newValue
                        viewModel.applyFilters()
                    }
                ),
                endDate: Binding(
                    get: { viewModel.filterState.timeRangeEnd },
                    set: { newValue in
                        viewModel.filterState.timeRangeEnd = newValue
                        viewModel.applyFilters()
                    }
                )
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    @MainActor
    private func toggleLevel(_ level: LogLevel, enabled: Bool) {
        if enabled {
            viewModel.filterState.enabledLevels.insert(level)
        } else {
            viewModel.filterState.enabledLevels.remove(level)
        }
        viewModel.applyFilters()
    }

    @MainActor
    private func selectAllLevels() {
        viewModel.filterState.enabledLevels = Set(LogLevel.allCases)
        viewModel.applyFilters()
    }

    @MainActor
    private func deselectAllLevels() {
        viewModel.filterState.enabledLevels = []
        viewModel.applyFilters()
    }
}

/// Individual log level toggle button
private struct LogLevelToggle: View {
    let level: LogLevel
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button(action: {
            onToggle(!isEnabled)
        }) {
            HStack(spacing: 4) {
                // Level indicator dot
                Circle()
                    .fill(isEnabled ? level.color : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)

                Text(level.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isEnabled ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isEnabled ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isEnabled ? level.color.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(level.rawValue) - \(isEnabled ? "Enabled" : "Disabled")")
        .accessibilityLabel("\(level.rawValue) log level filter")
        .accessibilityValue(isEnabled ? "enabled" : "disabled")
        .accessibilityHint("Toggle \(level.rawValue) log entries visibility")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

struct FilterBar_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            FilterBar(viewModel: {
                let vm = LogViewModel()
                vm.filterState.enabledLevels = Set(LogLevel.allCases)
                return vm
            }())
            .frame(width: 800)
            .previewDisplayName("All Enabled")

            FilterBar(viewModel: {
                let vm = LogViewModel()
                vm.filterState.enabledLevels = [.error, .warning, .info]
                return vm
            }())
            .frame(width: 800)
            .previewDisplayName("Some Disabled")

            FilterBar(viewModel: {
                let vm = LogViewModel()
                vm.filterState.enabledLevels = Set(LogLevel.allCases)
                return vm
            }())
            .frame(width: 800)
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
        }
    }
}
