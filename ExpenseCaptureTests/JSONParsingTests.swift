import XCTest
@testable import ExpenseCapture

final class JSONParsingTests: XCTestCase {

    var service: GLMVisionService!

    override func setUp() {
        super.setUp()
        service = GLMVisionService.shared
    }

    // MARK: - 基础用例

    func testSimpleObject() {
        let input = "{\"key\": \"value\"}"
        XCTAssertEqual(service.extractOutermostObject(from: input), "{\"key\": \"value\"}")
    }

    func testNestedObject() {
        let input = "{\"a\": {\"b\": \"c\"}}"
        XCTAssertEqual(service.extractOutermostObject(from: input), "{\"a\": {\"b\": \"c\"}}")
    }

    // MARK: - 字符串值含花括号

    func testStringValueWithCurlyBraces() {
        let input = "{\"note\": \"a{b}c\"}"
        XCTAssertEqual(service.extractOutermostObject(from: input), "{\"note\": \"a{b}c\"}")
    }

    // MARK: - 字符串值含转义引号

    func testStringValueWithEscapedQuotes() {
        // JSON 字符串值中含有转义引号 \"，函数应正确跳过，不在转义引号处截断
        let input = #"{"x": "he said \"hi\""}"#
        // 完整对象与输入相同（没有多余噪声）
        XCTAssertEqual(service.extractOutermostObject(from: input), #"{"x": "he said \"hi\""}"#)
    }

    // MARK: - 前后有噪声文本

    func testNoisyPrefix() {
        let input = #"Some noise before {"k":"v"} and after"#
        XCTAssertEqual(service.extractOutermostObject(from: input), #"{"k":"v"}"#)
    }

    func testMarkdownCodeBlock() {
        let input = "prefix\n{\"amount\": 6.9}\nsuffix"
        XCTAssertEqual(service.extractOutermostObject(from: input), "{\"amount\": 6.9}")
    }

    // MARK: - 多个对象 → 只取第一个

    func testMultipleObjects() {
        let input = "{\"first\": 1}{\"second\": 2}"
        XCTAssertEqual(service.extractOutermostObject(from: input), "{\"first\": 1}")
    }

    // MARK: - 无 { 的纯文本

    func testNoCurlyBrace() {
        XCTAssertNil(service.extractOutermostObject(from: "no json here"))
    }

    func testEmptyString() {
        XCTAssertNil(service.extractOutermostObject(from: ""))
    }

    // MARK: - 不平衡括号（缺 }）

    func testUnbalancedBrackets() {
        XCTAssertNil(service.extractOutermostObject(from: "{\"key\": \"val\" "))
    }

    // MARK: - 带数组的对象

    func testObjectWithArray() {
        let input = "{\"items\": [1, 2, 3]}"
        XCTAssertEqual(service.extractOutermostObject(from: input), "{\"items\": [1, 2, 3]}")
    }

    // MARK: - 真实 GLM 回包格式

    func testRealGLMCoreResponse() {
        let input = """
        {
          "amount": 6.9,
          "merchant": "古茗",
          "transactionDate": "2024-03-15 14:30"
        }
        """
        let result = service.extractOutermostObject(from: input)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"amount\""))
        XCTAssertTrue(result!.contains("\"merchant\""))
        XCTAssertTrue(result!.contains("\"transactionDate\""))
    }

    func testRealGLMDetailResponse() {
        let input = """
        Here is the result:
        {"subCategory": "奶茶", "notes": null}
        """
        let result = service.extractOutermostObject(from: input)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"subCategory\""))
    }
}
