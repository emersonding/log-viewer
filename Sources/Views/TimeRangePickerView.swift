//
//  TimeRangePickerView.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import SwiftUI

/// Time range filter with date pickers (including seconds) and quick presets
struct TimeRangePickerView: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?

    @State private var isStartDateEnabled: Bool = false
    @State private var isEndDateEnabled: Bool = false
    @State private var localStartDate: Date = Date()
    @State private var localEndDate: Date = Date()
    @State private var startSeconds: Int = 0
    @State private var endSeconds: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Text("Time Range:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()

            // Start date picker
            HStack(spacing: 4) {
                Toggle("From:", isOn: $isStartDateEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .fixedSize()
                    .onChange(of: isStartDateEnabled) { _, newValue in
                        startDate = newValue ? composedDate(localStartDate, seconds: startSeconds) : nil
                    }
                    .accessibilityLabel("Enable start date filter")
                    .accessibilityValue(isStartDateEnabled ? "enabled" : "disabled")

                DatePicker(
                    "",
                    selection: $localStartDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .disabled(!isStartDateEnabled)
                .onChange(of: localStartDate) { _, newValue in
                    if isStartDateEnabled {
                        startDate = composedDate(newValue, seconds: startSeconds)
                    }
                }
                .frame(width: 180)
                .accessibilityLabel("Start date and time")

                // Seconds field
                Text(":")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("ss", value: $startSeconds, format: .number)
                    .frame(width: 30)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(!isStartDateEnabled)
                    .onChange(of: startSeconds) { _, newValue in
                        startSeconds = max(0, min(59, newValue))
                        if isStartDateEnabled {
                            startDate = composedDate(localStartDate, seconds: startSeconds)
                        }
                    }
                    .accessibilityLabel("Start seconds")
            }

            // End date picker
            HStack(spacing: 4) {
                Toggle("To:", isOn: $isEndDateEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .fixedSize()
                    .onChange(of: isEndDateEnabled) { _, newValue in
                        endDate = newValue ? composedDate(localEndDate, seconds: endSeconds) : nil
                    }
                    .accessibilityLabel("Enable end date filter")
                    .accessibilityValue(isEndDateEnabled ? "enabled" : "disabled")

                DatePicker(
                    "",
                    selection: $localEndDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .disabled(!isEndDateEnabled)
                .onChange(of: localEndDate) { _, newValue in
                    if isEndDateEnabled {
                        endDate = composedDate(newValue, seconds: endSeconds)
                    }
                }
                .frame(width: 180)
                .accessibilityLabel("End date and time")

                // Seconds field
                Text(":")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("ss", value: $endSeconds, format: .number)
                    .frame(width: 30)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(!isEndDateEnabled)
                    .onChange(of: endSeconds) { _, newValue in
                        endSeconds = max(0, min(59, newValue))
                        if isEndDateEnabled {
                            endDate = composedDate(localEndDate, seconds: endSeconds)
                        }
                    }
                    .accessibilityLabel("End seconds")
            }

            Divider()
                .frame(height: 16)

            // Quick presets
            Text("Quick:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("Last 5 min") {
                applyPreset(minutes: 5)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .accessibilityLabel("Filter to last 5 minutes")

            Button("Last 1 hour") {
                applyPreset(hours: 1)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .accessibilityLabel("Filter to last hour")

            Button("Last 24 hours") {
                applyPreset(hours: 24)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .accessibilityLabel("Filter to last 24 hours")

            Button("Today") {
                applyTodayPreset()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .accessibilityLabel("Filter to today")

            Divider()
                .frame(height: 16)

            Button("Clear") {
                clearTimeRange()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundColor(.red)
            .accessibilityLabel("Clear time range filter")

            Spacer()
        }
        .onAppear {
            if let start = startDate {
                localStartDate = start
                startSeconds = Calendar.current.component(.second, from: start)
                isStartDateEnabled = true
            }
            if let end = endDate {
                localEndDate = end
                endSeconds = Calendar.current.component(.second, from: end)
                isEndDateEnabled = true
            }
        }
    }

    // MARK: - Helpers

    /// Compose a Date from a DatePicker date (which has 0 seconds) + explicit seconds
    private func composedDate(_ date: Date, seconds: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = seconds
        return calendar.date(from: components) ?? date
    }

    // MARK: - Preset Actions

    private func applyPreset(minutes: Int = 0, hours: Int = 0) {
        let now = Date()
        let timeInterval = TimeInterval(minutes * 60 + hours * 3600)
        let start = now.addingTimeInterval(-timeInterval)

        localStartDate = start
        localEndDate = now
        startSeconds = Calendar.current.component(.second, from: start)
        endSeconds = Calendar.current.component(.second, from: now)
        isStartDateEnabled = true
        isEndDateEnabled = true

        startDate = start
        endDate = now
    }

    private func applyTodayPreset() {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        localStartDate = startOfDay
        localEndDate = now
        startSeconds = 0
        endSeconds = calendar.component(.second, from: now)
        isStartDateEnabled = true
        isEndDateEnabled = true

        startDate = startOfDay
        endDate = now
    }

    private func clearTimeRange() {
        isStartDateEnabled = false
        isEndDateEnabled = false
        startDate = nil
        endDate = nil
    }
}
