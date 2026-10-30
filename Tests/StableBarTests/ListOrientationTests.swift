import Foundation
import Testing
@testable import StableBar

@Test func listOrientationDefaultsToVerticalAndRejectsUnknownDirections() throws {
    for property in ["", #","orientation":null"#, #","orientation":"vertical""#] {
        let data = Data(#"{"type":"list","source":"apps","row":{"type":"field","field":"badge"}\#(property)}"#.utf8)
        let block = try JSONDecoder().decode(PopupBlock.self, from: data)
        guard case let .list(_, _, orientation) = block.content else {
            Issue.record("Expected a list")
            return
        }
        #expect(orientation == .vertical)
    }
    let invalid = Data(#"{"type":"list","source":"apps","orientation":"diagonal","row":{"type":"field","field":"badge"}}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(PopupBlock.self, from: invalid) }
}

@Test func listOrientationComposesThroughModulesTemplatesAndProfiles() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(#"""
    {"templates":{"apps":{"type":"script","command":"true","position":"right",
      "layout":{"type":"list","source":"apps","orientation":"vertical","row":{"type":"field","field":"badge"}}}}}
    """#.utf8).write(to: directory.appending(path: "module.json"))
    let json = #"""
    {"includes":["module.json"],"tokens":{"direction":"horizontal"},
     "widgets":[{"id":"badges","template":"apps"}],
     "widgetOverrides":{"badges":{"layout":{"orientation":"@token.direction"}}},
     "profiles":[{"name":"stacked","when":{"onBattery":true},
       "configuration":{"widgetOverrides":{"badges":{"layout":{"orientation":"vertical"}}}}}]}
    """#
    var loader = ConfigurationLoader()
    let url = directory.appending(path: "config.json")
    let horizontal = try loader.load(url, data: Data(json.utf8))
    let vertical = try loader.load(url, data: Data(json.utf8), context: ConfigurationContext(onBattery: true))
    guard case let .list(_, _, normal) = horizontal.widgets[0].layout?.content,
          case let .list(_, _, battery) = vertical.widgets[0].layout?.content else {
        Issue.record("Expected composed list layouts")
        return
    }
    #expect(normal == .horizontal)
    #expect(battery == .vertical)
}
