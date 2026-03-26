import Foundation

// MARK: - Expense Extraction (from Claude Vision)

struct ExpenseExtraction: Codable {
    let amount: Double
    let currency: String
    let category: String
    let merchant: String
    let paymentChannel: String?    // 支付渠道：微信/支付宝/京东/拼多多等
    let transactionDate: String?
    let notes: String?
}

// MARK: - Expense Record (local storage)

struct ExpenseRecord: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let currency: String
    let category: String
    let merchant: String
    let paymentChannel: String
    let transactionDate: String?
    let notes: String?
    let recordedAt: Date

    init(from extraction: ExpenseExtraction) {
        self.id = UUID()
        self.amount = abs(extraction.amount)
        self.currency = extraction.currency.isEmpty ? "CNY" : extraction.currency
        self.category = extraction.category.isEmpty ? "其他" : extraction.category
        self.merchant = extraction.merchant.isEmpty ? "未知商户" : extraction.merchant
        self.paymentChannel = extraction.paymentChannel ?? "未知"
        self.transactionDate = extraction.transactionDate
        self.notes = extraction.notes
        self.recordedAt = Date()
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
    private let maxRecords = 20

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
