//
//  FileWatcher.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import Foundation

/// Monitors a file for changes and notifies via callback with debouncing
@MainActor
final class FileWatcher {

    // MARK: - Properties

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var callback: (@Sendable () -> Void)?
    private let debounceDelay: TimeInterval = 0.5 // 500ms

    // MARK: - Lifecycle

    init() {}

    deinit {
        // Synchronous cleanup in deinit
        debounceTask?.cancel()
        dispatchSource?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    // MARK: - Public Methods

    /// Starts monitoring the file at the given path
    /// - Parameters:
    ///   - path: The file path to monitor
    ///   - callback: Callback invoked on main actor after debounce period
    func start(path: String, callback: @escaping @Sendable () -> Void) {
        // Stop any existing monitoring
        stop()

        // Store the callback
        self.callback = callback

        // Open the file descriptor
        fileDescriptor = open(path, O_EVTONLY)

        // If file doesn't exist or can't be opened, return gracefully
        guard fileDescriptor >= 0 else {
            return
        }

        // Create dispatch source for file system events
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        // Event handler
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let source = self.dispatchSource else { return }

                let eventMask = source.data

                // Handle file deletion or permission revocation
                if eventMask.contains(.delete) || eventMask.contains(.revoke) {
                    // Capture callback before stopping (stop nils it)
                    let cb = self.callback

                    // Stop watching the file
                    self.stop()

                    // Trigger callback immediately for deletion/revocation
                    cb?()
                    return
                }

                // Normal write/rename events - debounce the callback
                // Cancel existing debounce task
                self.debounceTask?.cancel()

                // Capture callback to avoid accessing it from task closure
                guard let callback = self.callback else { return }

                let delay = self.debounceDelay
                self.debounceTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    if !Task.isCancelled {
                        callback()
                    }
                }
            }
        }

        // Cancellation handler - close file descriptor
        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }

        // Store source and activate
        dispatchSource = source
        source.resume()
    }

    /// Stops monitoring the file
    func stop() {
        // Cancel debounce task
        debounceTask?.cancel()
        debounceTask = nil

        // Cancel dispatch source (this will trigger cancelHandler which closes fd)
        dispatchSource?.cancel()
        dispatchSource = nil

        // Reset file descriptor
        fileDescriptor = -1

        // Clear callback
        callback = nil
    }
}
