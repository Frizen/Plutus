import Foundation

// MARK: - Log Entry

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String, Codable {
        case info = "ℹ️"
        case success = "✅"
        case warning = "⚠️"
        case error = "❌"
        case debug = "🔍"
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

// MARK: - Logger

class IntentLogger {
    static let shared = IntentLogger()

    private let storageKey = "intent_run_logs"
    private let maxEntries = 100
    private let queue = DispatchQueue(label: "com.expensecapture.logger", qos: .utility)

    private init() {}

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(id: UUID(), timestamp: Date(), level: level, message: message)
        queue.async {
            var entries = self.loadEntries()
            entries.insert(entry, at: 0)
            if entries.count > self.maxEntries {
                entries = Array(entries.prefix(self.maxEntries))
            }
            if let data = try? JSONEncoder().encode(entries) {
                UserDefaults.standard.set(data, forKey: self.storageKey)
            }
        }
    }

    func loadEntries() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
