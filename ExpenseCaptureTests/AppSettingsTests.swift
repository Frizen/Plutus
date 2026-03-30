import XCTest
@testable import ExpenseCapture

final class AppSettingsTests: XCTestCase {

    // 每个测试用独立的 AppSettings 实例，避免共享 UserDefaults 污染
    var settings: AppSettings!

    override func setUp() {
        super.setUp()
        // 使用内存 UserDefaults suite 隔离测试数据
        let suiteName = "com.expensecapture.tests.\(UUID().uuidString)"
        settings = AppSettings()
        // 清空相关字段
        settings.bitableAppToken = ""
        settings.tableID = ""
    }

    override func tearDown() {
        settings = nil
        super.tearDown()
    }

    // MARK: - 空 / 空白字符串

    func testEmptyString() {
        let result = settings.parseBitableURL("")
        XCTAssertNil(result, "空字符串应返回 nil")
    }

    func testWhitespaceOnly() {
        let result = settings.parseBitableURL("   \t\n  ")
        XCTAssertNil(result, "纯空白字符串应返回 nil")
    }

    // MARK: - 非飞书域名

    func testNonFeishuDomain() {
        let result = settings.parseBitableURL("https://www.example.com/base/ABC123?table=tbl123")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.success)
        XCTAssertTrue(result!.message.contains("格式不正确"), "非飞书域名应提示格式不正确，实际：\(result!.message)")
    }

    // MARK: - 飞书域名但无 /base/

    func testFeishuDomainWithoutBasePath() {
        let result = settings.parseBitableURL("https://feishu.cn/wiki/some-page")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.success)
        XCTAssertTrue(result!.message.contains("未找到 /base/"), "缺少 /base/ 应给出对应提示，实际：\(result!.message)")
    }

    // MARK: - 有 appToken 但无 table 参数

    func testMissingTableID() {
        let result = settings.parseBitableURL("https://feishu.cn/base/MyAppToken123")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.success)
        XCTAssertTrue(result!.message.contains("缺少 Table ID"), "缺少 table 参数应提示缺少 Table ID，实际：\(result!.message)")
        // appToken 仍应写入
        XCTAssertEqual(settings.bitableAppToken, "MyAppToken123")
    }

    // MARK: - feishu.cn 完整链接

    func testFullFeishuCnURL() {
        let result = settings.parseBitableURL("https://feishu.cn/base/AppToken456?table=tblXYZ789")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.success)
        XCTAssertTrue(result!.message.contains("解析成功"), "完整链接应解析成功，实际：\(result!.message)")
        XCTAssertEqual(settings.bitableAppToken, "AppToken456")
        XCTAssertEqual(settings.tableID, "tblXYZ789")
    }

    // MARK: - larkoffice.com 完整链接

    func testFullLarkOfficeURL() {
        let result = settings.parseBitableURL("https://larkoffice.com/base/Lark999?table=tblLark001")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.success)
        XCTAssertEqual(settings.bitableAppToken, "Lark999")
        XCTAssertEqual(settings.tableID, "tblLark001")
    }

    // MARK: - 带 from= 冗余参数的链接

    func testURLWithExtraQueryParams() {
        let url = "https://feishu.cn/base/TokenABC?table=tblDEF&from=from_copylink"
        let result = settings.parseBitableURL(url)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.success)
        XCTAssertEqual(settings.bitableAppToken, "TokenABC")
        XCTAssertEqual(settings.tableID, "tblDEF")
    }

    // MARK: - 链接前后有空格

    func testURLWithLeadingTrailingSpaces() {
        let result = settings.parseBitableURL("  https://feishu.cn/base/SpaceToken?table=tblSpc  ")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.success)
        XCTAssertEqual(settings.bitableAppToken, "SpaceToken")
        XCTAssertEqual(settings.tableID, "tblSpc")
    }
}
