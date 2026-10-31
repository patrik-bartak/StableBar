import Foundation

struct AeroSpaceTree: Decodable, Sendable {
    let focusedWindowId: Int?
    let workspaces: [Space]

    struct Space: Decodable, Sendable {
        let workspace: String
        let isFocused: Bool
        let isVisible: Bool
        let monitorAppKitNsScreenScreensId: Int
        let root: Node
        let floatingWindows: [Node]
        let fullscreenWindows: [Node]
        let hiddenWindows: [Node]

        var snapshot: Workspace {
            let windows = ([root] + floatingWindows + fullscreenWindows + hiddenWindows)
                .flatMap { $0.windows(in: workspace) }
            var bundleIDs = Set<String>()
            return Workspace(name: workspace, isFocused: isFocused, isVisible: isVisible,
                monitor: monitorAppKitNsScreenScreensId,
                apps: windows.map(\.app).filter { bundleIDs.insert($0.bundleID).inserted },
                windows: windows, hasTreeOrder: true)
        }
    }

    indirect enum Node: Decodable, Sendable {
        case container(layout: String, orientation: String, children: [Node])
        case window(id: Int, title: String, appName: String, appBundleId: String)

        private enum CodingKeys: String, CodingKey {
            case type, layout, orientation, children, windowId, title, appName, appBundleId
        }
        private enum Kind: String, Decodable { case container, window }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            switch try values.decode(Kind.self, forKey: .type) {
            case .container:
                self = .container(layout: try values.decode(String.self, forKey: .layout),
                    orientation: try values.decode(String.self, forKey: .orientation),
                    children: try values.decode([Node].self, forKey: .children))
            case .window:
                self = .window(id: try values.decode(Int.self, forKey: .windowId),
                    title: try values.decodeIfPresent(String.self, forKey: .title) ?? "",
                    appName: try values.decodeIfPresent(String.self, forKey: .appName) ?? "",
                    appBundleId: try values.decodeIfPresent(String.self, forKey: .appBundleId) ?? "")
            }
        }

        func windows(in workspace: String) -> [WorkspaceWindow] {
            switch self {
            case let .container(_, _, children): children.flatMap { $0.windows(in: workspace) }
            case let .window(id, title, name, bundleID):
                [WorkspaceWindow(id: id, title: title,
                    app: WorkspaceApp(workspace: workspace, name: name, bundleID: bundleID))]
            }
        }
    }

    var snapshot: [Workspace] {
        workspaces.map(\.snapshot).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
