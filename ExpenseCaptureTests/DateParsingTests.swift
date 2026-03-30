import XCTest
@testable import ExpenseCapture

final class DateParsingTests: XCTestCase {

    var service: FeishuBitableService!

    override func setUp() {
        super.setUp()
        service = FeishuBitableService.shared
    }

    // MARK: - 辅助：把毫秒时间戳还原为 Date

    private func msToDate(_ ms: Int) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    // MARK: - 合法格式（11 种）

    func testFormat_yyyyMMddHHmmss() {
        let ms = service.parseToTimestampMs("2024-03-15 14:30:00")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(comps.second, 0)
    }

    func testFormat_yyyyMMddHHmm() {
        let ms = service.parseToTimestampMs("2024-03-15 14:30")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFormat_yyyyMMdd() {
        let ms = service.parseToTimestampMs("2024-03-15")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testFormat_slashYYYYMMddHHmmss() {
        let ms = service.parseToTimestampMs("2024/03/15 14:30:00")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFormat_slashYYYYMMddHHmm() {
        let ms = service.parseToTimestampMs("2024/03/15 14:30")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testFormat_slashYYYYMMdd() {
        let ms = service.parseToTimestampMs("2024/03/15")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testFormat_chineseFullDatetime() {
        let ms = service.parseToTimestampMs("2024年03月15日 14:30:00")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFormat_chineseDateHHmm() {
        let ms = service.parseToTimestampMs("2024年03月15日 14:30")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testFormat_chineseDateOnly() {
        let ms = service.parseToTimestampMs("2024年03月15日")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testFormat_MMddHHmm_dash() {
        // MM-dd HH:mm 格式（当年）
        let ms = service.parseToTimestampMs("03-15 14:30")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    func testFormat_MMddHHmm_slash() {
        // MM/dd HH:mm 格式（当年）
        let ms = service.parseToTimestampMs("03/15 14:30")
        let date = msToDate(ms)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    // MARK: - 前后有空格

    func testTrimsWhitespace() {
        let msWithSpace    = service.parseToTimestampMs("  2024-03-15 14:30  ")
        let msWithoutSpace = service.parseToTimestampMs("2024-03-15 14:30")
        XCTAssertEqual(msWithSpace, msWithoutSpace, "前后空格应被 trim 后再解析")
    }

    // MARK: - 兜底逻辑（空字符串 / 无效格式）

    func testFallbackOnEmptyString() {
        let before = Int(Date().timeIntervalSince1970 * 1000)
        let ms = service.parseToTimestampMs("")
        let after  = Int(Date().timeIntervalSince1970 * 1000)
        XCTAssertGreaterThanOrEqual(ms, before - 1000, "空字符串应兜底当前时间戳（允许 1s 误差）")
        XCTAssertLessThanOrEqual(ms, after + 1000)
    }

    func testFallbackOnInvalidString() {
        let before = Int(Date().timeIntervalSince1970 * 1000)
        let ms = service.parseToTimestampMs("abc-invalid-date")
        let after  = Int(Date().timeIntervalSince1970 * 1000)
        XCTAssertGreaterThanOrEqual(ms, before - 1000, "无效格式应兜底当前时间戳（允许 1s 误差）")
        XCTAssertLessThanOrEqual(ms, after + 1000)
    }
}
