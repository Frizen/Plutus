import Foundation

// MARK: - Phase 1: 核心字段（金额、商户、时间）

struct CoreExtraction: Codable {
    let amount: Double
    let merchant: String
    let transactionDate: String?
}

// MARK: - Phase 2: 详情字段（分类、备注）

struct DetailExtraction: Codable {
    let subCategory: String
    let notes: String?
}

// MARK: - Expense Record (local storage)

struct ExpenseRecord: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let currency: String
    var category: String
    let merchant: String
    let transactionDate: String?
    var notes: String?
    let recordedAt: Date
    var userName: String       // 记账成员，旧记录解码时为空字符串
    var needsPhase2: Bool      // Phase 2 尚未完成时为 true，用于 UI 展示「分类待定」

    // CodingKeys：保持 JSON key 为 "subCategory"，兼容旧版本本地存储
    enum CodingKeys: String, CodingKey {
        case id, amount, currency, merchant, transactionDate, notes, recordedAt, userName, needsPhase2
        case category = "subCategory"
    }

    // 自定义解码：userName / needsPhase2 为新字段，旧数据中不存在时使用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,   forKey: .id)
        amount          = try c.decode(Double.self, forKey: .amount)
        currency        = try c.decode(String.self, forKey: .currency)
        category        = try c.decode(String.self, forKey: .category)
        merchant        = try c.decode(String.self, forKey: .merchant)
        transactionDate = try c.decodeIfPresent(String.self, forKey: .transactionDate)
        notes           = try c.decodeIfPresent(String.self, forKey: .notes)
        recordedAt      = try c.decode(Date.self,   forKey: .recordedAt)
        userName        = (try? c.decodeIfPresent(String.self, forKey: .userName)) ?? ""
        needsPhase2     = (try? c.decodeIfPresent(Bool.self, forKey: .needsPhase2)) ?? false
    }

    // Phase 1：仅核心字段，分类待补全（needsPhase2 = true 表示 Phase 2 尚未完成）
    init(from core: CoreExtraction, userName: String = "") {
        self.id = UUID()
        self.amount = abs(core.amount)
        self.currency = "CNY"
        self.category = "其他"
        self.merchant = core.merchant.isEmpty ? "未知商户" : core.merchant
        self.transactionDate = core.transactionDate
        self.notes = nil
        self.recordedAt = Date()
        self.userName = userName
        self.needsPhase2 = true
    }

    // Phase 2：用详情字段生成更新后的副本，同时清除 needsPhase2 标记
    func withDetail(_ detail: DetailExtraction) -> ExpenseRecord {
        var updated = self
        updated.category = detail.subCategory.isEmpty ? "其他" : detail.subCategory
        updated.notes = detail.notes
        updated.needsPhase2 = false
        return updated
    }

    var displayAmount: String {
        let symbol: String
        switch currency.uppercased() {
        case "CNY": symbol = "¥"
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        case "JPY": symbol = "¥"
        default: symbol = currency + " "
        }
        return "\(symbol)\(String(format: "%.2f", amount))"
    }

    var displayDate: String {
        if let dateStr = transactionDate, !dateStr.isEmpty {
            return dateStr
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: recordedAt)
    }
}

// MARK: - Local Record Store（单例，避免多实例数据不同步）

class ExpenseRecordStore: ObservableObject {
    static let shared = ExpenseRecordStore()

    @Published var records: [ExpenseRecord] = []

    private let storageKey = "expense_records"
    private let maxRecords = 1000

    private init() {
        load()
    }

    func add(_ record: ExpenseRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    // Phase 2 回调：用详情字段更新已有记录
    func update(id: UUID, with detail: DetailExtraction) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index] = records[index].withDetail(detail)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ExpenseRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    func clear() {
        records = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func reload() {
        load()
    }
}
