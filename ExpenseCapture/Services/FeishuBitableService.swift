import Foundation

// MARK: - Errors

enum FeishuError: LocalizedError {
    case configMissing
    case tokenFetchFailed(String)
    case networkError(Error)
    case invalidResponse(Int, String)
    case encodingFailed
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .configMissing: return "飞书配置不完整，请检查 App ID / Secret / Bitable 配置"
        case .tokenFetchFailed(let msg): return "获取飞书 Token 失败: \(msg)"
        case .networkError(let e): return "网络错误: \(e.localizedDescription)"
        case .invalidResponse(let code, let msg): return "飞书 API 错误 [\(code)]: \(msg)"
        case .encodingFailed: return "请求编码失败"
        case .decodingFailed(let msg): return "响应解析失败: \(msg)"
        }
    }
}

// MARK: - Token Cache

private struct TokenCache {
    var token: String
    var expiresAt: Date

    var isValid: Bool {
        // 提前 5 分钟刷新
        Date() < expiresAt.addingTimeInterval(-300)
    }
}

// MARK: - Feishu API Models

private struct TenantTokenRequest: Encodable {
    let app_id: String
    let app_secret: String
}

private struct TenantTokenResponse: Decodable {
    let code: Int
    let msg: String
    let tenant_access_token: String?
    let expire: Int?
}

private struct BitableRecordRequest: Encodable {
    let fields: [String: BitableFieldValue]
}

private enum BitableFieldValue: Encodable {
    case string(String)
    case number(Double)
    case int(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        }
    }
}

private struct BitableRecordResponse: Decodable {
    let code: Int
    let msg: String
    let data: BitableRecordData?
}

private struct BitableRecordData: Decodable {
    let record: BitableRecord?
}

private struct BitableRecord: Decodable {
    let record_id: String?
}

// MARK: - Service（单例，token 缓存在 Phase 1 / Phase 2 间复用）

class FeishuBitableService {
    static let shared = FeishuBitableService()

    private let tokenEndpoint = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
    private let bitableEndpoint = "https://open.feishu.cn/open-apis/bitable/v1/apps"

    private var tokenCache: TokenCache?

    private init() {}

    // MARK: - Public API

    func addRecord(expense: ExpenseRecord, appID: String, appSecret: String, appToken: String, tableID: String, fieldNames: FeishuFieldNames) async throws -> String {
        guard !appID.isEmpty, !appSecret.isEmpty, !appToken.isEmpty, !tableID.isEmpty else {
            throw FeishuError.configMissing
        }
        let token = try await getValidToken(appID: appID, appSecret: appSecret)
        return try await writeRecord(expense: expense, token: token, appToken: appToken, tableID: tableID, fieldNames: fieldNames)
    }

    // MARK: - Token Management

    private func getValidToken(appID: String, appSecret: String) async throws -> String {
        if let cache = tokenCache, cache.isValid {
            return cache.token
        }
        return try await fetchFreshToken(appID: appID, appSecret: appSecret)
    }

    private func fetchFreshToken(appID: String, appSecret: String) async throws -> String {
        let requestBody = TenantTokenRequest(app_id: appID, app_secret: appSecret)

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FeishuError.tokenFetchFailed("HTTP 请求失败")
        }

        let tokenResponse = try JSONDecoder().decode(TenantTokenResponse.self, from: data)

        guard tokenResponse.code == 0,
              let token = tokenResponse.tenant_access_token,
              let expireSeconds = tokenResponse.expire else {
            throw FeishuError.tokenFetchFailed("code=\(tokenResponse.code), msg=\(tokenResponse.msg)")
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(expireSeconds))
        tokenCache = TokenCache(token: token, expiresAt: expiresAt)
        return token
    }

    // MARK: - Write Record

    private func writeRecord(expense: ExpenseRecord, token: String, appToken: String, tableID: String, fieldNames: FeishuFieldNames) async throws -> String {
        let urlString = "\(bitableEndpoint)/\(appToken)/tables/\(tableID)/records"
        guard let url = URL(string: urlString) else {
            throw FeishuError.encodingFailed
        }

        var fields: [String: BitableFieldValue] = [
            fieldNames.amount:   .number(expense.amount),
            fieldNames.merchant: .string(expense.merchant)
        ]

        if !expense.userName.isEmpty {
            fields[fieldNames.userName] = .string(expense.userName)
        }

        if let dateStr = expense.transactionDate, !dateStr.isEmpty {
            fields[fieldNames.date] = .int(parseToTimestampMs(dateStr))
        } else {
            fields[fieldNames.date] = .int(Int(Date().timeIntervalSince1970 * 1000))
        }

        let requestBody = BitableRecordRequest(fields: fields)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuError.networkError(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw FeishuError.invalidResponse(httpResponse.statusCode, bodyStr)
        }

        let recordResponse = try JSONDecoder().decode(BitableRecordResponse.self, from: data)
        guard recordResponse.code == 0 else {
            throw FeishuError.invalidResponse(recordResponse.code, recordResponse.msg)
        }

        guard let recordID = recordResponse.data?.record?.record_id else {
            throw FeishuError.decodingFailed("未返回 record_id")
        }
        return recordID
    }

    // MARK: - Date Parsing

    /// 把 GLM 返回的各种日期字符串解析为飞书要求的毫秒时间戳
    /// 解析失败时兜底返回当前时间戳
    private func parseToTimestampMs(_ dateStr: String) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "yyyy年MM月dd日 HH:mm:ss",
            "yyyy年MM月dd日 HH:mm",
            "yyyy年MM月dd日",
            "MM-dd HH:mm",
            "MM/dd HH:mm",
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateStr.trimmingCharacters(in: .whitespaces)) {
                return Int(date.timeIntervalSince1970 * 1000)
            }
        }

        IntentLogger.shared.log("日期解析失败，使用当前时间兜底。原始值: \(dateStr)", level: .warning)
        return Int(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Test Connection

    func testConnection(appID: String, appSecret: String, appToken: String, tableID: String) async throws -> String {
        guard !appID.isEmpty, !appSecret.isEmpty, !appToken.isEmpty, !tableID.isEmpty else {
            throw FeishuError.configMissing
        }
        _ = try await fetchFreshToken(appID: appID, appSecret: appSecret)
        return "连接成功，Token 获取正常 ✓"
    }
}

// MARK: - Field Names

struct FeishuFieldNames {
    let amount:    String
    let merchant:  String
    let date:      String
    let notes:     String
    let userName:  String

    init(settings: AppSettings) {
        self.amount   = settings.fieldAmount
        self.merchant = settings.fieldMerchant
        self.date     = settings.fieldDate
        self.notes    = settings.fieldNotes
        self.userName = settings.fieldUserName
    }
}
