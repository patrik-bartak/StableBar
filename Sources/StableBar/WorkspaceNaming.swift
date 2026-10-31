import AppKit
import SwiftUI

extension ConfigurationEdit {
    static func workspaceName(_ id: String, name: String, source: WorkspaceSource) -> ConfigurationEdit {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfigurationEdit(action: .workspaceNames, properties: [
            source.rawValue: .object([id: name.isEmpty ? .null : .string(name)])
        ])
    }
}

extension BarStore {
    func workspaceName(_ id: String, source: WorkspaceSource) -> String? {
        configuration?.workspaceNames[source.rawValue]?[id]
    }

    func requestWorkspaceName(_ id: String? = nil) throws {
        guard let id = id ?? workspaceStore.workspaces.first(where: \.isFocused)?.name,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommandFailure(message: "No focused workspace is available. Supply a workspace ID or reconnect the workspace manager.")
        }
        guard let onNameWorkspace else { throw CommandFailure(message: "Workspace naming is unavailable.") }
        let url = configurationURL
        let source = configuration?.workspaceSource ?? workspaceStore.source
        // Return the control reply before opening a window for a keyboard shortcut.
        Task { @MainActor [weak self] in
            guard self?.configurationURL == url, self?.configuration?.workspaceSource == source else { return }
            onNameWorkspace(id, source)
        }
    }

    func saveWorkspaceName(_ id: String, name: String, source: WorkspaceSource) throws {
        try customizationHistory.change([ConfigurationEdit.workspaceName(id, name: name, source: source)])
        try customizationHistory.flush()
    }
}

@MainActor
final class WorkspaceNamingWindow {
    private var window: NSWindow?

    func show(store: BarStore, id: String, source: WorkspaceSource) {
        window?.close()
        let url = store.configurationURL
        let profile = store.customizationHistory.editingProfile
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 190),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Name workspace \(id)"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = NSHostingView(rootView: WorkspaceNamingView(id: id, source: source,
            name: store.workspaceName(id, source: source) ?? "", save: { name in
                guard store.configurationURL == url, store.configuration?.workspaceSource == source,
                      store.customizationHistory.editingProfile == profile else {
                    throw CommandFailure(message: "The configuration changed. Open Name workspace again.")
                }
                try store.saveWorkspaceName(id, name: name, source: source)
            }, close: { [weak window] in window?.close() }))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct WorkspaceNamingView: View {
    let id: String
    let source: WorkspaceSource
    @State var name: String
    let save: (String) throws -> Void
    let close: () -> Void
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(source.title) workspace \(id)").font(.headline)
            TextField("Workspace name", text: $name)
                .focused($focused)
                .onSubmit(commit)
            Text("Leave empty to clear the name.").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save", action: commit).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func commit() {
        do { try save(name); close() }
        catch { self.error = errorMessage(error) }
    }
}

struct WorkspaceNamesSettings: View {
    let editor: ConfigurationEditor

    var body: some View {
        let store = editor.store
        let source = store.configuration?.workspaceSource ?? .aerospace
        let names = store.configuration?.workspaceNames[source.rawValue] ?? [:]
        let ids = Set(store.workspaceStore.workspaces.map(\.name)).union(names.keys)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if ids.isEmpty {
            SettingRow(title: "Workspace names", hint: "Workspaces appear here when connected.") {}
        }
        ForEach(ids, id: \.self) { id in
            SettingRow(title: "Workspace \(id)", hint: names[id] ?? "No custom name") {
                Button("Name…") {
                    editor.finishEditing()
                    do { try store.requestWorkspaceName(id) }
                    catch { editor.error = errorMessage(error) }
                }
                .controlSize(.small)
            }
        }
    }
}
