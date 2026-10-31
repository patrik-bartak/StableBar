import AppKit
import Testing
@testable import StableBar

@Test func workspaceNamesKeepIDsAndSourceDisplayNames() throws {
    let workspace = Workspace(name: "3", isFocused: true, isVisible: true, monitor: 1, displayName: "Web")
    #expect(workspace.label(alias: "Research") == "3: Research")
    #expect(workspace.label(alias: nil) == "Web")
    #expect(workspace.id == "3")
    let configuration = try JSONDecoder().decode(Configuration.self, from: Data(#"""
    {"workspaceNames":{"aerospace":{"3":"Research","a=b":"Café 🐈","4":null},"spaces":{"3":"Personal"},"yabai":null},"widgets":[]}
    """#.utf8))
    #expect(configuration.workspaceNames == ["aerospace": ["3": "Research", "a=b": "Café 🐈"], "spaces": ["3": "Personal"]])
    #expect(try JSONDecoder().decode(Configuration.self, from: Data(#"{"widgets":[]}"#.utf8)).workspaceNames.isEmpty)
}

@Test(arguments: [#"{"other":{"1":"Code"}}"#, #"{"aerospace":{"":"Code"}}"#,
                  #"{"aerospace":{"1":"  "}}"#, #"{"aerospace":{"1":123}}"#, #"{"aerospace":{"":null}}"#])
func workspaceNamesRejectInvalidMappings(mapping: String) {
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(Configuration.self, from: Data("{\"workspaceNames\":\(mapping),\"widgets\":[]}".utf8))
    }
}

@Test func workspaceNamesMergeIncludesAndProfilesAndClearInheritedNames() throws {
    let fixture = try ThemeGalleryFixture(#"""
    {"includes":["base.json"],"workspaceNames":{"aerospace":{"2":"Chat"}},"profile":"work",
     "profiles":[{"name":"work","configuration":{"workspaceNames":{"aerospace":{"1":null,"3":"Research"}}}}],
     "widgets":[]}
    """#)
    defer { fixture.close() }
    let base = #"{"workspaceNames":{"aerospace":{"1":"Code","2":"Web"},"spaces":{"1":"Personal"}}}"#
    try fixture.write(base, to: fixture.directory.appending(path: "base.json"))
    var loader = ConfigurationLoader()
    let configuration = try loader.load(fixture.url)
    #expect(configuration.workspaceNames == ["aerospace": ["2": "Chat", "3": "Research"], "spaces": ["1": "Personal"]])
    #expect(loader.activeProfiles == ["work"])
    #expect(try String(contentsOf: fixture.directory.appending(path: "base.json"), encoding: .utf8) == base)
}

@Test @MainActor func workspaceNamesSaveClearUndoAndPreserveTemporaryEdits() throws {
    let fixture = try ThemeGalleryFixture(#"{"includes":["base.json"],"widgets":[]}"#)
    defer { fixture.close() }
    let base = #"{"workspaceNames":{"aerospace":{"1":"Code"},"spaces":{"1":"Personal"}}}"#
    let baseURL = fixture.directory.appending(path: "base.json")
    try fixture.write(base, to: baseURL)
    let store = BarStore(configurationURL: fixture.url)
    defer { store.stop() }
    store.reloadConfiguration()
    try store.applyEdits([ConfigurationEdit(action: .bar, properties: ["height": .number(52)])], persist: false)
    try store.saveWorkspaceName("1", name: "  Research 🐈  ", source: .aerospace)
    #expect(store.workspaceName("1", source: .aerospace) == "Research 🐈")
    #expect(store.workspaceName("1", source: .spaces) == "Personal")
    #expect(try fixture.document()["bar"] == nil)
    #expect(store.configuration?.bar.height == 52)
    #expect(store.sessionEdits.count == 1)
    try store.saveWorkspaceName("1", name: "  ", source: .aerospace)
    #expect(store.workspaceName("1", source: .aerospace) == nil)
    let document = try fixture.document()
    let names = try #require(try document["workspaceNames"]?.decoded([String: [String: ConfigurationValue]].self))
    #expect(names["aerospace"]?["1"] == .null)
    store.reloadConfiguration()
    #expect(store.workspaceName("1", source: .aerospace) == nil)
    try store.customizationHistory.undo()
    #expect(store.workspaceName("1", source: .aerospace) == "Research 🐈")
    try store.customizationHistory.redo()
    #expect(store.workspaceName("1", source: .aerospace) == nil)
    #expect(try String(contentsOf: baseURL, encoding: .utf8) == base)
}

@Test @MainActor func workspaceNamesCanBeEditedInProfiles() throws {
    let fixture = try ThemeGalleryFixture(#"""
    {"workspaceNames":{"aerospace":{"1":"Personal"}},
     "profile":"work","profiles":[{"name":"work","configuration":{}}],"widgets":[]}
    """#)
    defer { fixture.close() }
    let store = BarStore(configurationURL: fixture.url)
    defer { store.stop() }
    store.reloadConfiguration()
    store.customizationHistory.editingProfile = "work"
    try store.saveWorkspaceName("1", name: "Code", source: .aerospace)
    #expect(store.workspaceName("1", source: .aerospace) == "Code")
    #expect(try fixture.document()["workspaceNames"] == .object(["aerospace": .object(["1": .string("Personal")])]))
    try store.customizationHistory.undo()
    #expect(store.workspaceName("1", source: .aerospace) == "Personal")
}

@Test func workspaceNamesCommandsAddressTheSelectedConfiguration() throws {
    for (arguments, id, name, persist) in [
        (["--name-workspace"], nil, nil, false),
        (["--name-workspace", "3"], "3", nil, false),
        (["--name-workspace", "3", "Research"], "3", "Research", false),
        (["--name-workspace", "3", "", "--persist"], "3", "", true)
    ] as [([String], String?, String?, Bool)] {
        guard case let .control(url, request) = try LaunchCommand(arguments: ["--config", "/tmp/names-test.json"] + arguments) else {
            Issue.record("Expected a runtime request"); continue
        }
        #expect(url.path == "/tmp/names-test.json")
        #expect(request.action == .nameWorkspace)
        #expect(request.id == id)
        #expect(request.name == name)
        #expect(request.persist == persist)
        let roundTrip = try JSONDecoder().decode(RuntimeRequest.self, from: JSONEncoder().encode(request))
        #expect(roundTrip.name == name)
    }
    for arguments in [["--name-workspace", "--persist"], ["--name-workspace", "3", "--persist"],
                      ["--name-workspace", "3", "Research", "extra"]] {
        #expect(throws: CommandFailure.self) { try LaunchCommand(arguments: arguments) }
    }
}

@Test @MainActor func workspaceNamesRuntimeEditsUseTheConfiguredSourceAndValidateAtomically() throws {
    let fixture = try ThemeGalleryFixture(#"{"workspaceSource":"spaces","widgets":[]}"#)
    defer { fixture.close() }
    let store = BarStore(configurationURL: fixture.url)
    defer { store.stop() }
    store.reloadConfiguration()
    _ = try store.handle(RuntimeRequest(action: .nameWorkspace, id: "3", name: "Personal"))
    #expect(store.workspaceName("3", source: .spaces) == "Personal")
    #expect(try fixture.document()["workspaceNames"] == nil)
    _ = try store.handle(RuntimeRequest(action: .nameWorkspace, id: "3", name: "Personal", persist: true))
    let saved = try Data(contentsOf: fixture.url)
    #expect(throws: (any Error).self) {
        try store.handle(RuntimeRequest(action: .nameWorkspace, id: "", name: "Invalid", persist: true))
    }
    #expect(try Data(contentsOf: fixture.url) == saved)
    #expect(store.workspaceName("3", source: .spaces) == "Personal")
    _ = try store.handle(RuntimeRequest(action: .nameWorkspace, id: "3", name: "", persist: true))
    #expect(store.workspaceName("3", source: .spaces) == nil)
    #expect(store.workspaceName("3", source: .aerospace) == nil)
}

@Test @MainActor func workspaceNamesDialogCapturesTheFocusedWorkspaceBeforeReturning() async throws {
    let fixture = try ThemeGalleryFixture()
    defer { fixture.close() }
    let store = try fixture.store()
    defer { store.stop() }
    store.workspaceStore.workspaces = [Workspace(name: "3", isFocused: true, isVisible: true, monitor: 1)]
    var requested: [(String, WorkspaceSource)] = []
    store.onNameWorkspace = { requested.append(($0, $1)) }
    _ = try store.handle(RuntimeRequest(action: .nameWorkspace))
    #expect(requested.isEmpty)
    store.workspaceStore.workspaces = []
    for _ in 0..<10 where requested.isEmpty { await Task.yield() }
    #expect(requested.count == 1)
    #expect(requested.first?.0 == "3")
    #expect(requested.first?.1 == .aerospace)
    #expect(throws: CommandFailure.self) { try store.handle(RuntimeRequest(action: .nameWorkspace)) }
}

@Test func workspaceNamesBelongToUsersRatherThanPackages() throws {
    let document: [String: ConfigurationValue] = ["workspaceNames": .object(["aerospace": .object(["1": .string("Code")])])]
    for nested in [document, ["profiles": .array([.object(["name": .string("work"), "configuration": .object(document)])])]] {
        #expect(throws: (any Error).self) { try validateThemeDocument(nested) }
        #expect(throws: (any Error).self) { try validateWidgetsDocument(nested) }
        #expect(throws: (any Error).self) { try validateCommandPackagePresentation(nested) }
    }
}

@Test @MainActor func workspaceNamesWidenCellsAndRefreshWithoutChangingIdentity() async throws {
    let configuration = try JSONDecoder().decode(Configuration.self, from: Data(#"""
    {"bar":{"height":36},"widgets":[{"id":"spaces","type":"workspaces","position":"left"}]}
    """#.utf8))
    let workspace = Workspace(name: "3", isFocused: true, isVisible: true, monitor: 1,
        apps: [WorkspaceApp(workspace: "3", name: "Finder", bundleID: "com.apple.finder")])
    let fixture = OffscreenBar(configuration: configuration,
        display: BarDisplay(id: 1, isBuiltIn: false, isMain: true, notch: nil), width: 700, workspaces: [workspace])
    defer { fixture.close() }
    await fixture.settle()
    let before = try #require(fixture.anchors("spaces").first).bounds.width
    _ = try fixture.bitmap(name: "workspace-names-before")
    fixture.store.configuration = try JSONDecoder().decode(Configuration.self, from: Data(#"""
    {"bar":{"height":36},"workspaceNames":{"aerospace":{"3":"Research"}},
     "widgets":[{"id":"spaces","type":"workspaces","position":"left"}]}
    """#.utf8))
    await fixture.settle()
    let after = try #require(fixture.anchors("spaces").first).bounds.width
    #expect(after > before + 40)
    #expect(workspace.label(alias: fixture.store.workspaceName("3", source: .aerospace)) == "3: Research")
    #expect(fixture.store.workspaceStore.workspaces == [workspace])
    _ = try fixture.bitmap(name: "workspace-names-after")
}
