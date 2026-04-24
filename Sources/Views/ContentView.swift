//
//  ContentView.swift
//  Lumen
//
//  Created on 2026-04-13.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @Environment(LogViewModel.self) private var viewModel
    @State private var focusSearchBar: Bool = false
    @State private var fieldNameInput: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .environment(viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.currentFileURL == nil {
                    welcomeView
                } else if viewModel.errorMessage != nil {
                    errorView
                } else {
                    mainContentView
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle(windowTitle)
        .onAppear {
            columnVisibility = viewModel.isSidebarVisible ? .all : .detailOnly
        }
        .onChange(of: viewModel.isSidebarVisible) { _, newValue in
            withAnimation {
                columnVisibility = newValue ? .all : .detailOnly
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            let shouldBeVisible = newValue != .detailOnly
            if viewModel.isSidebarVisible != shouldBeVisible {
                viewModel.setSidebarVisible(shouldBeVisible)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), presenting: viewModel.errorMessage) { _ in
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: { errorMessage in
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            focusSearchBar = true
        }
    }

    // MARK: - Window Title

    private var windowTitle: String {
        guard let url = viewModel.currentFileURL else {
            return "Lumen"
        }

        let filename = url.lastPathComponent
        let path = url.path
        return "Lumen - \(filename) - \(path)"
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Log file viewer icon")

            Text("Open a log file to get started")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open a log file to get started")

            Button("Open File") {
                openFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityLabel("Open log file")
            .accessibilityHint("Opens a file picker to select a log file")

            Text("or drag and drop a file here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome screen")
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.loadingProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 300)
                .accessibilityLabel("Loading progress")
                .accessibilityValue("\(Int(viewModel.loadingProgress * 100)) percent")

            let phase = viewModel.loadingProgress < 0.3 ? "Indexing lines..." : "Parsing entries..."
            let percent = Int(viewModel.loadingProgress * 100)

            Text("\(phase) \(percent)%")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let url = viewModel.currentFileURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loading log file")
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.red)
                .accessibilityLabel("Error icon")

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            HStack(spacing: 12) {
                Button("Dismiss") {
                    viewModel.errorMessage = nil
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Dismiss error")
                .accessibilityHint("Closes the error message")

                Button("Open Another File") {
                    viewModel.errorMessage = nil
                    openFilePicker()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open another file")
                .accessibilityHint("Opens file picker to select a different log file")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error screen")
    }

    // MARK: - Main Content View

    @MainActor
    private var mainContentView: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: 0) {
            // Search and file actions
            HStack(spacing: 8) {
                SearchBar(shouldBeFocused: $focusSearchBar)

                Button {
                    Task {
                        await vm.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }
                .buttonStyle(.bordered)
                .disabled(vm.currentFileURL == nil || vm.isLoading)
                .help("Refresh file")
                .accessibilityLabel("Refresh file")
                .accessibilityHint("Reads new content from the current log file")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }

            // Filter bar
            FilterBar(viewModel: vm)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Divider()
                }

            extractedFieldsBar(vm: vm)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Divider()
                }

            // Log table view (AppKit NSTableView for performance with large files)
            AppKitLogTableView(viewModel: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Status bar
            StatusBarView(viewModel: vm)
        }
    }

    private func extractedFieldsBar(vm: LogViewModel) -> some View {
        HStack(spacing: 8) {
            TextField("field", text: $fieldNameInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 160)
                .onSubmit {
                    addExtractedField(vm)
                }
                .accessibilityLabel("Field name")
                .accessibilityHint("Enter a key-value field name to add as a log table column")

            Button {
                addExtractedField(vm)
            } label: {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
            }
            .buttonStyle(.bordered)
            .disabled(!canAddExtractedField(vm))
            .help("Add field column")
            .accessibilityLabel("Add field column")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.extractedFieldNames, id: \.self) { fieldName in
                        HStack(spacing: 4) {
                            Text(fieldName)
                                .font(.system(.caption, design: .monospaced))

                            Button {
                                vm.removeExtractedField(fieldName)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .accessibilityHidden(true)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remove \(fieldName)")
                            .accessibilityLabel("Remove \(fieldName)")
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 28, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func canAddExtractedField(_ vm: LogViewModel) -> Bool {
        let name = fieldNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return vm.extractedFieldNames.count < LogViewModel.maxExtractedFields &&
            vm.isValidExtractedFieldName(name) &&
            !vm.extractedFieldNames.contains(name)
    }

    private func addExtractedField(_ vm: LogViewModel) {
        guard canAddExtractedField(vm) else { return }
        vm.addExtractedField(fieldNameInput)
        fieldNameInput = ""
    }

    // MARK: - File Operations

    /// Open system file picker
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "log")!,
            .init(filenameExtension: "txt")!,
            .data  // All files
        ]
        panel.message = "Select a log file to open"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.openFile(url: url)
                }
            }
        }
    }

    /// Handle drag-and-drop of files
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                await viewModel.openFile(url: url)
            }
        }

        return true
    }
}

// MARK: - Previews
// Note: Preview macros removed for Swift Package Manager compatibility
