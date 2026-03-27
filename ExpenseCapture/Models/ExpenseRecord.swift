import Foundation

// MARK: - Phase 1: 核心字段（金额、商户、时间）

struct CoreExtraction: Codable {
    let amount: Double
    let merchant: String
    let transactionDate: String?
}

// MARK: - Phase 2: 详情字段（二级分类、备注）

struct DetailExtraction: Codable {
    let subCategory: String
    let notes: String?
}

// MARK: - 一级分类推导

func primaryCategory(from subCategory: String) -> String {
    switch subCategory {
    case "外出就餐", "外卖", "水果", "零食", "买菜", "奶茶", "饮料酒水":
        return "餐饮"
    case "物业费", "水电燃气", "电器", "手机话费":
        return "居家生活"
    case "红包", "礼物":
        return "人情费用"
    case "地铁公交", "长途交通", "打车":
        return "行车交通"
    case "生活用品", "电子数码", "美妆护肤", "衣裤鞋帽", "书报杂志", "珠宝首饰", "宠物", "美发":
        return "购物消费"
    case "医疗", "药物":
        return "医疗"
    case "慈善":
        return "公益"
    case "娱乐", "旅游", "按摩", "运动":
        return "休闲娱乐"
    case "保险":
        return "保险"
    default:
        return "其他"
    }
}

// MARK: - Expense Record (local storage)

struct ExpenseRecord: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let currency: String
    var subCategory: String
    var primaryCategory: String
    let merchant: String
    let transactionDate: String?
    var notes: String?
    let recordedAt: Date

    // Phase 1：仅核心字段，分类待补全
    init(from core: CoreExtraction) {
        self.id = UUID()
        self.amount = abs(core.amount)
        self.currency = "CNY"
        self.subCategory = "其他"
        self.primaryCategory = "其他"
        self.merchant = core.merchant.isEmpty ? "未知商户" : core.merchant
        self.transactionDate = core.transactionDate
        self.notes = nil
        self.recordedAt = Date()
    }

    // Phase 2：用详情字段生成更新后的副本
    func withDetail(_ detail: DetailExtraction) -> ExpenseRecord {
        var updated = self
        let sub = detail.subCategory.isEmpty ? "其他" : detail.subCategory
        updated.subCategory = sub
        updated.primaryCategory = ExpenseCapture.primaryCategory(from: sub)
        updated.notes = detail.notes
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

// MARK: - Local Record Store

class ExpenseRecordStore: ObservableObject {
    @Published var records: [ExpenseRecord] = []

    private let storageKey = "expense_records"
    private let maxRecords = 100

    init() {
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
}
