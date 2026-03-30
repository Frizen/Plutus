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

/// 线程安全的轻量级日志记录器。
/// - 使用内存缓存（`_entries`）作为唯一数据源，避免每次 `log()` 全量读写 UserDefaults。
/// - 每次写入后通过 `DispatchWorkItem` 延迟 1s 批量落盘（debounce），高频写入时只触发一次 IO。
class IntentLogger {
    static let shared = IntentLogger()

    private let storageKey = "intent_run_logs"
    private let maxEntries = 100
    private let queue = DispatchQueue(label: "com.expensecapture.logger", qos: .utility)

    // 内存缓存：在 queue 上访问
    private var _entries: [LogEntry] = []
    // 延迟落盘的 work item（可取消）
    private var _pendingFlush: DispatchWorkItem?

    private init() {
        // 启动时从 UserDefaults 加载到内存
        queue.async { self._entries = self._loadFromDisk() }
    }

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(id: UUID(), timestamp: Date(), level: level, message: message)
        queue.async {
            self._entries.insert(entry, at: 0)
            if self._entries.count > self.maxEntries {
                self._entries = Array(self._entries.prefix(self.maxEntries))
            }
            self._scheduleDeferredFlush()
        }
    }

    /// 供外部（LogView）调用：通过 queue.sync 保证线程安全，直接返回内存数据
    func loadEntries() -> [LogEntry] {
        queue.sync { _entries }
    }

    func clear() {
        queue.async {
            self._entries = []
            self._pendingFlush?.cancel()
            self._pendingFlush = nil
            UserDefaults.standard.removeObject(forKey: self.storageKey)
        }
    }

    // MARK: - Private

    /// 安排一次延迟 1s 的批量落盘（上一个未执行的 work item 会被取消）
    private func _scheduleDeferredFlush() {
        _pendingFlush?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self._flushToDisk()
        }
        _pendingFlush = item
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func _flushToDisk() {
        if let data = try? JSONEncoder().encode(_entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func _loadFromDisk() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
