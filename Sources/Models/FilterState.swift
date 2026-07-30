//
//  FilterState.swift
//  Lumen
//
//  Created on 2026-04-13.
//

import Foundation

/// State for log level and time range filtering
struct FilterState: Codable, Sendable {
    private static let currentLevelFilterVersion = 1

    var enabledLevels: Set<LogLevel>
    var timeRangeStart: Date?
    var timeRangeEnd: Date?

    private enum CodingKeys: String, CodingKey {
        case enabledLevels
        case timeRangeStart
        case timeRangeEnd
        case levelFilterVersion
    }

    init(
        enabledLevels: Set<LogLevel> = Set(LogLevel.allCases),
        timeRangeStart: Date? = nil,
        timeRangeEnd: Date? = nil
    ) {
        self.enabledLevels = enabledLevels
        self.timeRangeStart = timeRangeStart
        self.timeRangeEnd = timeRangeEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decodedLevels = try container.decode(Set<LogLevel>.self, forKey: .enabledLevels)
        let version = try container.decodeIfPresent(Int.self, forKey: .levelFilterVersion)

        // Pre-UNDEFINED saved filters have no schema marker. Preserve their prior
        // behavior by enabling the new bucket during the one-time migration.
        if version == nil {
            decodedLevels.insert(.undefined)
        }

        enabledLevels = decodedLevels
        timeRangeStart = try container.decodeIfPresent(Date.self, forKey: .timeRangeStart)
        timeRangeEnd = try container.decodeIfPresent(Date.self, forKey: .timeRangeEnd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledLevels, forKey: .enabledLevels)
        try container.encodeIfPresent(timeRangeStart, forKey: .timeRangeStart)
        try container.encodeIfPresent(timeRangeEnd, forKey: .timeRangeEnd)
        try container.encode(Self.currentLevelFilterVersion, forKey: .levelFilterVersion)
    }

    /// Returns true if all filters are in their default state
    var isDefault: Bool {
        return enabledLevels.count == LogLevel.allCases.count &&
               timeRangeStart == nil &&
               timeRangeEnd == nil
    }
}
