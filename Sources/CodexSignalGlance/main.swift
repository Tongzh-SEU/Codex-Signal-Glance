import AppKit
import Foundation

let snapshotService = QuotaSnapshotService()

if CommandLine.arguments.contains("--once") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    if let snapshot = snapshotService.latestSnapshot(), let data = try? encoder.encode(snapshot) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        exit(EXIT_SUCCESS)
    } else {
        FileHandle.standardError.write("No quota snapshot found in ~/.codex/sessions\n".data(using: .utf8)!)
        exit(EXIT_FAILURE)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
