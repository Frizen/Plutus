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
        LogEntry.timeFormatter.string(from: timestamp)
    }

    // static 避免每次访问 timeString 时重复创建 DateFormatter
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
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
            var entries = self._loadEntries()
            entries.insert(entry, at: 0)
            if entries.count > self.maxEntries {
                entries = Array(entries.prefix(self.maxEntries))
            }
            if let data = try? JSONEncoder().encode(entries) {
                UserDefaults.standard.set(data, forKey: self.storageKey)
            }
        }
    }

    // 供外部（LogView）调用：通过 queue.sync 保证线程安全
    func loadEntries() -> [LogEntry] {
        queue.sync { _loadEntries() }
    }

    // 内部使用，必须在 queue 上调用
    private func _loadEntries() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func clear() {
        queue.async {
            UserDefaults.standard.removeObject(forKey: self.storageKey)
        }
    }
}
