//
//  LogEntry.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import AppKit
import Foundation
import SwiftUI

/// Represents a single log entry
struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let lineNumber: Int
    let timestamp: Date?
    let level: LogLevel?
    let message: String
    let rawLine: String

    init(
        id: UUID = UUID(),
        lineNumber: Int,
        timestamp: Date? = nil,
        level: LogLevel? = nil,
        message: String,
        rawLine: String
    ) {
        self.id = id
        self.lineNumber = lineNumber
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.rawLine = rawLine
    }
}

/// Log severity levels
enum LogLevel: String, CaseIterable, Sendable {
    case fatal = "FATAL"
    case error = "ERROR"
    case warning = "WARNING"
    case info = "INFO"
    case debug = "DEBUG"
    case trace = "TRACE"

    /// Returns the color for this log level, adaptive for light and dark mode
    var color: Color {
        switch self {
        case .fatal:
            return .red
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            #if os(macOS)
            // Blue in light mode, default in dark mode
            return Color(nsColor: .controlAccentColor)
            #else
            return .blue
            #endif
        case .debug:
            return .gray
        case .trace:
            return Color(.systemGray)
        }
    }

    /// Returns the background color for FATAL level (white text on red background)
    var backgroundColor: Color? {
        switch self {
        case .fatal:
            return .red
        default:
            return nil
        }
    }

    /// Returns the foreground color (text color)
    var foregroundColor: Color? {
        switch self {
        case .fatal:
            return .white
        default:
            return color
        }
    }

    /// SF Symbol icon name for this log level
    var iconName: String {
        switch self {
        case .fatal: return "xmark.octagon.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.triangle"
        case .info: return "info.circle"
        case .debug: return "ant"
        case .trace: return "line.3.horizontal"
        }
    }

    /// NSColor for AppKit rendering
    var nsColor: NSColor {
        switch self {
        case .fatal: return .systemRed
        case .error: return .systemRed
        case .warning: return .systemOrange
        case .info: return .controlAccentColor
        case .debug: return .systemGray
        case .trace: return .systemGray
        }
    }
}
