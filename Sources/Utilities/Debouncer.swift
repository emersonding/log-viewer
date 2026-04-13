//
//  Debouncer.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import Foundation

/// A thread-safe debouncer that delays action execution until a specified time passes without new trigger calls.
///
/// When `trigger()` is called, it resets a timer. The action fires only after `delay` seconds
/// have elapsed without any new triggers. This is useful for debouncing rapid events like
/// file changes or search input.
///
/// Example:
/// ```swift
/// let debouncer = Debouncer(delay: 0.5) {
///     print("This runs after 0.5 seconds of inactivity")
/// }
///
/// debouncer.trigger() // Starts timer
/// debouncer.trigger() // Resets timer
/// debouncer.trigger() // Resets timer again
/// // After 0.5 seconds of no triggers, action fires
/// ```
actor Debouncer {
    private let delay: TimeInterval
    private let action: @Sendable () -> Void
    private var task: Task<Void, Never>?

    /// Initialize a debouncer.
    ///
    /// - Parameters:
    ///   - delay: The time interval (in seconds) of inactivity before the action fires
    ///   - action: The closure to execute when the debounce delay elapses
    init(delay: TimeInterval, action: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.action = action
    }

    /// Trigger the debouncer, resetting the timer.
    ///
    /// Each call to `trigger()` resets the internal timer. The action will fire
    /// only after `delay` seconds have passed without a new call to `trigger()`.
    nonisolated func trigger() {
        Task {
            await _trigger()
        }
    }

    private func _trigger() {
        // Cancel existing task
        task?.cancel()

        // Schedule new task
        let delay = self.delay
        let action = self.action
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled {
                action()
            }
        }
    }

    /// Cancel the pending action execution.
    ///
    /// Stops the timer and prevents the action from firing unless `trigger()` is called again.
    nonisolated func cancel() {
        Task {
            await _cancel()
        }
    }

    private func _cancel() {
        task?.cancel()
        task = nil
    }
}
