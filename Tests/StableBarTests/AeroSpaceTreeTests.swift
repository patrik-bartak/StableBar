import AppKit
import Testing
@testable import StableBar

private let initialTreeEvent = #"""
{"_event":"workspace-tree-changed","tree":{"focusedWindowId":30,"workspaces":[
  {"workspace":"1","isFocused":true,"isVisible":true,"monitorAppKitNsScreenScreensId":1,
   "root":{"type":"container","layout":"tiles","orientation":"horizontal","children":[
     {"type":"window","windowId":30,"appName":"Terminal","appBundleId":"com.apple.Terminal","title":"Zebra"},
     {"type":"container","layout":"tiles","orientation":"vertical","children":[
       {"type":"window","windowId":10,"appName":"Finder","appBundleId":"com.apple.finder","title":"Alpha"},
       {"type":"window","windowId":20,"appName":"Terminal","appBundleId":"com.apple.Terminal","title":"Beta"}]}]},
   "floatingWindows":[],"fullscreenWindows":[],"hiddenWindows":[]},
  {"workspace":"2","isFocused":false,"isVisible":true,"monitorAppKitNsScreenScreensId":2,
   "root":{"type":"container","layout":"accordion","orientation":"vertical","children":[]},
   "floatingWindows":[],"fullscreenWindows":[],"hiddenWindows":[]}
]}}
"""#

private func treeEvent(_ json: String = initialTreeEvent) throws -> AeroSpaceEvent {
    // The subscription protocol uses one JSON object per line.
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try JSONDecoder().decode(AeroSpaceEvent.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func aerospaceTreeKeepsNestedWindowOrderAndRepeatedApps() throws {
    let tree = try #require(treeEvent().tree)
    let spaces = tree.snapshot
    #expect(spaces.map(\.name) == ["1", "2"])
    #expect(spaces[0].windows.map(\.id) == [30, 10, 20])
    #expect(spaces[0].windows.map(\.title) == ["Zebra", "Alpha", "Beta"])
    #expect(spaces[0].windows.map(\.app.name) == ["Terminal", "Finder", "Terminal"])
    #expect(spaces[0].hasTreeOrder)
    #expect(spaces[0].isFocused)
    #expect(spaces[1].isVisible)
    #expect(!spaces[1].isFocused)
    #expect(spaces[1].monitor == 2)
    #expect(spaces[1].windows.isEmpty)
}

@Test @MainActor func aerospaceTreeRejectsOlderRevisionsAndMissingSnapshots() throws {
    let store = WorkspaceStore()
    var current = try treeEvent()
    current.revision = 5
    store.receive(current)
    var stale = try treeEvent(initialTreeEvent.replacingOccurrences(of: "\"windowId\":30", with: "\"windowId\":99"))
    stale.revision = 4
    store.receive(stale)
    #expect(store.workspaces[0].windows.first?.id == 30)
    var missing = current
    missing.tree = nil
    store.receive(missing)
    #expect(store.error?.contains("missing") == true)
    #expect(store.workspaces[0].windows.first?.id == 30)
}

@Test @MainActor func aerospaceTreeStreamUpdatesAndReconnectsWithoutListQueries() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appending(path: "aerospace")
    let object = try JSONSerialization.jsonObject(with: Data(initialTreeEvent.utf8))
    let initial = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try initial.write(to: directory.appending(path: "initial.json"))
    var updatedObject = try #require(object as? [String: Any])
    var tree = try #require(updatedObject["tree"] as? [String: Any])
    var spaces = try #require(tree["workspaces"] as? [[String: Any]])
    var root = try #require(spaces[0]["root"] as? [String: Any])
    var children = try #require(root["children"] as? [[String: Any]])
    var nested = try #require(children[1]["children"] as? [[String: Any]])
    let last = nested.popLast()
    let moved = try #require(last)
    children[1]["children"] = nested
    root["children"] = children
    spaces[0]["root"] = root
    var destination = try #require(spaces[1]["root"] as? [String: Any])
    destination["children"] = [moved]
    spaces[1]["root"] = destination
    tree["workspaces"] = spaces
    updatedObject["tree"] = tree
    try JSONSerialization.data(withJSONObject: updatedObject).write(to: directory.appending(path: "updated.json"))
    try Data("""
    #!/bin/sh
    cd '\(directory.path)'
    printf '%s\\n' "$*" >> calls
    case "$1" in
      subscribe)
        cat initial.json; printf '\\n'
        while [ ! -f update ]; do /bin/sleep 0.01; done
        cat updated.json; printf '\\n'
        exec /bin/sleep 30 ;;
      move-node-to-workspace) touch update ;;
      *) echo 'Unexpected follow-up command' >&2; exit 1 ;;
    esac
    """.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let store = WorkspaceStore()
    store.executablePath = { executable.path }
    store.configure(source: .aerospace, workspaces: true, mode: true)
    defer { store.stop() }
    for _ in 0..<200 where store.workspaces.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(try #require(store.workspaces.first).windows.map(\.id) == [30, 10, 20])
    store.refreshForDisplayChange()
    let payload = try #require(store.windowDrag.begin(source: .aerospace, windows: [store.workspaces[0].windows[2]]))
    let move = try #require(store.moveWindows(payload, to: "2"))
    await move.value
    for _ in 0..<500 where store.workspaces.last?.windows.first?.id != 20 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.workspaces.first(where: \.isFocused)?.name == "1")
    #expect(store.workspaces[0].windows.map(\.id) == [30, 10])
    #expect(store.workspaces[1].windows.map(\.id) == [20])
    store.reconnect()
    for _ in 0..<200 {
        let calls = (try? String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)) ?? ""
        if calls.split(separator: "\n").count == 3 && store.workspaces.last?.windows.first?.id == 20 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8).split(separator: "\n")
    #expect(calls == ["subscribe workspace-tree-changed mode-changed", "move-node-to-workspace --window-id 20 -- 2",
                     "subscribe workspace-tree-changed mode-changed"])
    #expect(store.error == nil)
}

@Test @MainActor func aerospaceTreeAcceptsRestartedServerRevisionsWithoutQueries() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appending(path: "aerospace")
    let initialObject = try #require(JSONSerialization.jsonObject(with: Data(initialTreeEvent.utf8)) as? [String: Any])
    var initial = initialObject
    initial["revision"] = 10
    try JSONSerialization.data(withJSONObject: initial).write(to: directory.appending(path: "initial.json"))
    var restarted = initialObject
    restarted["revision"] = 1
    var tree = try #require(restarted["tree"] as? [String: Any])
    var spaces = try #require(tree["workspaces"] as? [[String: Any]])
    spaces[0]["isFocused"] = false
    spaces[1]["isFocused"] = true
    tree["workspaces"] = spaces
    tree["focusedWindowId"] = NSNull()
    restarted["tree"] = tree
    try JSONSerialization.data(withJSONObject: restarted).write(to: directory.appending(path: "restarted.json"))
    try Data("""
    #!/bin/sh
    cd '\(directory.path)'
    printf '%s\\n' "$*" >> calls
    [ "$1" = subscribe ] || exit 1
    if [ ! -f started ]; then
      touch started; cat initial.json; printf '\\n'; exit 0
    fi
    cat restarted.json; printf '\\n'
    exec /bin/sleep 30
    """.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let store = WorkspaceStore()
    store.executablePath = { executable.path }
    store.reconnectDelay = 0.01
    store.start()
    defer { store.stop() }
    for _ in 0..<500 where store.workspaces.first(where: \.isFocused)?.name != "2" {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.workspaces.first(where: \.isFocused)?.name == "2")
    let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8).split(separator: "\n")
    #expect(calls == ["subscribe workspace-tree-changed mode-changed", "subscribe workspace-tree-changed mode-changed"])
    #expect(store.connectionError == nil)
}

@Test @MainActor func aerospaceTreeFallsBackWhenTheEventIsUnsupported() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appending(path: "aerospace")
    try Data("""
    #!/bin/sh
    cd '\(directory.path)'
    printf '%s\\n' "$*" >> calls
    case "$1" in
      subscribe)
        if [ "$2" = workspace-tree-changed ]; then
          echo "ERROR: Can't parse 'workspace-tree-changed'." >&2; exit 2
        fi
        printf '%s\\n' '{"_event":"mode-changed","mode":"main"}'
        exec /bin/sleep 30 ;;
      list-workspaces)
        printf '%s\\n' '[{"workspace":"1","workspace-is-focused":true,"workspace-is-visible":true,"monitor-appkit-nsscreen-screens-id":1}]' ;;
      list-windows) echo '[]' ;;
    esac
    """.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let store = WorkspaceStore()
    store.executablePath = { executable.path }
    store.start()
    defer { store.stop() }
    for _ in 0..<500 where store.workspaces.isEmpty || store.mode != "main" {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.workspaces.first?.name == "1")
    #expect(store.workspaces.first?.hasTreeOrder == false)
    #expect(store.mode == "main")
    let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)
    #expect(calls.contains("subscribe focused-workspace-changed focused-monitor-changed focus-changed window-detected mode-changed"))
    #expect(calls.contains("list-workspaces --all"))
    #expect(calls.contains("list-windows --all"))
}

@Test @MainActor func aerospaceTreeRendersOneIconPerWindowInTreeOrder() async throws {
    let configuration = try JSONDecoder().decode(Configuration.self, from: Data(#"""
    {"bar":{"height":40},"widgets":[{"id":"spaces","type":"workspaces","position":"left"}]}
    """#.utf8))
    let workspaces = try #require(treeEvent().tree).snapshot
    let fixture = OffscreenBar(configuration: configuration,
        display: BarDisplay(id: 1, isBuiltIn: false, isMain: true, notch: nil), width: 400, workspaces: workspaces)
    defer { fixture.close() }
    await fixture.settle()
    func sources(_ view: NSView) -> [WorkspaceWindowDragSourceView] {
        (view as? WorkspaceWindowDragSourceView).map { [$0] } ?? view.subviews.flatMap(sources)
    }
    let icons = sources(fixture.host).sorted {
        $0.convert($0.bounds, to: fixture.host).minX < $1.convert($1.bounds, to: fixture.host).minX
    }
    #expect(icons.map { $0.windows.map(\.id) } == [[30], [10], [20]])
    #expect(!fixture.panel.isVisible)
    _ = try fixture.bitmap(name: "workspace-tree-after")

    var before = workspaces
    before[0].hasTreeOrder = false
    before[0].apps.sort { $0.name < $1.name }
    let old = OffscreenBar(configuration: configuration,
        display: BarDisplay(id: 1, isBuiltIn: false, isMain: true, notch: nil), width: 400, workspaces: before)
    defer { old.close() }
    await old.settle()
    _ = try old.bitmap(name: "workspace-tree-before")
}
