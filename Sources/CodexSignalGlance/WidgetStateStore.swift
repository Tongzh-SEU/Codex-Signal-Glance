import Foundation

final class WidgetStateStore {
    private let stateURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedState: WidgetState?

    init(rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex-signal-glance")) {
        self.stateURL = rootDirectory.appendingPathComponent("state.json")
    }

    func load() -> WidgetState {
        if let cachedState {
            return cachedState
        }

        guard let data = try? Data(contentsOf: stateURL) else {
            let state = WidgetState()
            cachedState = state
            return state
        }
        let state = (try? decoder.decode(WidgetState.self, from: data)) ?? WidgetState()
        cachedState = state
        return state
    }

    func save(_ state: WidgetState) {
        cachedState = state
        let parent = stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    func update(_ transform: (inout WidgetState) -> Void) {
        var state = load()
        transform(&state)
        save(state)
    }
}
