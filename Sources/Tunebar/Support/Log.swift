import Foundation

/// Appends failures to ~/Library/Logs/Tunebar.log (viewable in Console.app).
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Tunebar.log")

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
