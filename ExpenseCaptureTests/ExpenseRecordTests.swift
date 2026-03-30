import XCTest
@testable import ExpenseCapture

final class ExpenseRecordTests: XCTestCase {

    // MARK: - 辅助工厂

    private func makeCoreExtraction(amount: Double = 28.5, merchant: String = "古茗", date: String? = "2024-03-15 14:30") -> CoreExtraction {
        CoreExtraction(amount: amount, merchant: merchant, transactionDate: date)
    }

    private func makeDetailExtraction(subCategory: String = "奶茶", notes: String? = "下午茶") -> DetailExtraction {
        DetailExtraction(subCategory: subCategory, notes: notes)
    }

    // MARK: - Phase 1 初始化

    func testPhase1InitNeedsPhase2() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        XCTAssertTrue(record.needsPhase2, "Phase 1 创建的记录应标记 needsPhase2 = true")
    }

    func testPhase1InitCategoryIsOther() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        XCTAssertEqual(record.category, "其他", "Phase 1 默认分类应为「其他」")
    }

    func testPhase1InitAmountIsAbsolute() {
        let record = ExpenseRecord(from: makeCoreExtraction(amount: -15.0))
        XCTAssertEqual(record.amount, 15.0, accuracy: 0.001, "amount 应取绝对值")
    }

    func testPhase1InitMerchantFallback() {
        let record = ExpenseRecord(from: makeCoreExtraction(merchant: ""))
        XCTAssertEqual(record.merchant, "未知商户", "商户名为空时应 fallback 为「未知商户」")
    }

    func testPhase1InitNotesIsNil() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        XCTAssertNil(record.notes, "Phase 1 初始化时 notes 应为 nil")
    }

    func testPhase1InitCurrencyIsCNY() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        XCTAssertEqual(record.currency, "CNY")
    }

    // MARK: - Phase 2：withDetail()

    func testWithDetailClearsNeedsPhase2() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        let updated = record.withDetail(makeDetailExtraction())
        XCTAssertFalse(updated.needsPhase2, "withDetail() 后 needsPhase2 应变为 false")
    }

    func testWithDetailUpdatesCategory() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        let updated = record.withDetail(makeDetailExtraction(subCategory: "外卖"))
        XCTAssertEqual(updated.category, "外卖")
    }

    func testWithDetailUpdatesNotes() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        let updated = record.withDetail(makeDetailExtraction(notes: "工作餐"))
        XCTAssertEqual(updated.notes, "工作餐")
    }

    func testWithDetailEmptySubCategoryFallback() {
        let record = ExpenseRecord(from: makeCoreExtraction())
        let updated = record.withDetail(makeDetailExtraction(subCategory: ""))
        XCTAssertEqual(updated.category, "其他", "subCategory 为空时 category 应 fallback 为「其他」")
    }

    // MARK: - 值语义：withDetail() 不改变原始记录

    func testWithDetailPreservesOriginal() {
        let original = ExpenseRecord(from: makeCoreExtraction())
        _ = original.withDetail(makeDetailExtraction())
        XCTAssertTrue(original.needsPhase2, "原始记录的 needsPhase2 不应被 withDetail() 修改（值语义）")
        XCTAssertEqual(original.category, "其他", "原始记录的 category 不应被修改")
    }

    // MARK: - Codable 往返

    func testCodableRoundTrip() throws {
        let core = makeCoreExtraction(amount: 38.0, merchant: "瑞幸", date: "2024-05-01 09:00")
        var record = ExpenseRecord(from: core)
        let detail = makeDetailExtraction(subCategory: "奶茶", notes: "早咖啡")
        record = record.withDetail(detail)

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ExpenseRecord.self, from: encoded)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.amount, record.amount, accuracy: 0.001)
        XCTAssertEqual(decoded.currency, record.currency)
        XCTAssertEqual(decoded.category, record.category)
        XCTAssertEqual(decoded.merchant, record.merchant)
        XCTAssertEqual(decoded.transactionDate, record.transactionDate)
        XCTAssertEqual(decoded.notes, record.notes)
        XCTAssertEqual(decoded.needsPhase2, record.needsPhase2)
    }

    // MARK: - 旧格式 JSON 解码兼容性（无 needsPhase2 字段）

    func testLegacyJSONDecoding() throws {
        // 模拟旧版本存储的 JSON（不含 needsPhase2 字段）
        let legacyJSON = """
        {
          "id": "12345678-1234-1234-1234-123456789abc",
          "amount": 12.5,
          "currency": "CNY",
          "subCategory": "外卖",
          "merchant": "美团",
          "transactionDate": "2024-01-01 12:00",
          "recordedAt": 1704067200.0,
          "userName": "张三"
        }
        """
        let data = Data(legacyJSON.utf8)
        let record = try JSONDecoder().decode(ExpenseRecord.self, from: data)

        XCTAssertFalse(record.needsPhase2, "旧格式 JSON 无 needsPhase2 字段时应兜底为 false")
        XCTAssertEqual(record.category, "外卖", "旧格式 JSON 中 subCategory 应映射为 category")
        XCTAssertEqual(record.merchant, "美团")
        XCTAssertEqual(record.userName, "张三")
    }

    func testLegacyJSONDecodingMissingUserName() throws {
        // 模拟更老版本：不含 userName
        let legacyJSON = """
        {
          "id": "12345678-1234-1234-1234-123456789abd",
          "amount": 5.0,
          "currency": "CNY",
          "subCategory": "打车",
          "merchant": "滴滴",
          "recordedAt": 1704067200.0
        }
        """
        let data = Data(legacyJSON.utf8)
        let record = try JSONDecoder().decode(ExpenseRecord.self, from: data)

        XCTAssertEqual(record.userName, "", "旧格式无 userName 时应兜底为空字符串")
        XCTAssertFalse(record.needsPhase2)
    }

    // MARK: - displayAmount

    func testDisplayAmountCNY() {
        let record = ExpenseRecord(from: makeCoreExtraction(amount: 28.5))
        XCTAssertEqual(record.displayAmount, "¥28.50")
    }

    func testDisplayAmountUSD() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789abc",
          "amount": 9.99,
          "currency": "USD",
          "subCategory": "娱乐",
          "merchant": "Netflix",
          "recordedAt": 1704067200.0,
          "userName": ""
        }
        """
        let record = try JSONDecoder().decode(ExpenseRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.displayAmount, "$9.99")
    }

    func testDisplayAmountEUR() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789abc",
          "amount": 5.00,
          "currency": "EUR",
          "subCategory": "购物",
          "merchant": "Amazon",
          "recordedAt": 1704067200.0,
          "userName": ""
        }
        """
        let record = try JSONDecoder().decode(ExpenseRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.displayAmount, "€5.00")
    }

    func testDisplayAmountUnknownCurrency() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789abc",
          "amount": 100.00,
          "currency": "SGD",
          "subCategory": "其他",
          "merchant": "Shop",
          "recordedAt": 1704067200.0,
          "userName": ""
        }
        """
        let record = try JSONDecoder().decode(ExpenseRecord.self, from: Data(json.utf8))
        XCTAssertTrue(record.displayAmount.hasPrefix("SGD "), "未知货币符号应以货币代码 + 空格开头，实际：\(record.displayAmount)")
        XCTAssertTrue(record.displayAmount.contains("100.00"))
    }
}
