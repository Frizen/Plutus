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

    // MARK: - Create Expense Bitable (Wizard Setup)

    /// 创建一个新的多维表格 App，建立记账所需字段，并开放「所有人可编辑」权限。
    /// 返回 (appToken, tableID)，权限设置失败时静默忽略。
    func createExpenseBitable(appID: String, appSecret: String) async throws -> (appToken: String, tableID: String) {
        let token = try await fetchFreshToken(appID: appID, appSecret: appSecret)
        let appToken = try await createBitableApp(token: token)
        let tableID  = try await getFirstTableID(token: token, appToken: appToken)
        try await createExpenseFields(token: token, appToken: appToken, tableID: tableID)
        try? await setPublicEditPermission(token: token, appToken: appToken)
        return (appToken, tableID)
    }

    private func createBitableApp(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: bitableEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": "Plutus 测试记账"])

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = json?["code"] as? Int, code == 0,
              let dataObj = json?["data"] as? [String: Any],
              let app = dataObj["app"] as? [String: Any],
              let appToken = app["app_token"] as? String else {
            let msg = (json?["msg"] as? String) ?? "解析失败"
            throw FeishuError.invalidResponse(-1, "创建多维表格失败: \(msg)")
        }
        return appToken
    }

    private func getFirstTableID(token: String, appToken: String) async throws -> String {
        // 飞书建表是异步的，接口返回后后端仍在初始化，items 可能暂时为空。
        // 最多重试 3 次，每次间隔 800ms。
        let url = URL(string: "\(bitableEndpoint)/\(appToken)/tables")!
        var lastError: Error = FeishuError.decodingFailed("无法获取 Table ID")

        for attempt in 1...3 {
            if attempt > 1 {
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let code = json?["code"] as? Int, code == 0,
               let dataObj = json?["data"] as? [String: Any],
               let items = dataObj["items"] as? [[String: Any]],
               let first = items.first,
               let tableID = first["table_id"] as? String {
                return tableID
            }
            lastError = FeishuError.decodingFailed("无法获取 Table ID（尝试 \(attempt)/3）")
        }
        throw lastError
    }

    private func createExpenseFields(token: String, appToken: String, tableID: String) async throws {
        let url = URL(string: "\(bitableEndpoint)/\(appToken)/tables/\(tableID)/fields")!

        // type 2 = 数字, type 1 = 多行文本, type 5 = 日期时间
        let fieldDefs: [[String: Any]] = [
            ["field_name": "金额",     "type": 2, "property": ["formatter": "0.00"]],
            ["field_name": "商户",     "type": 1],
            ["field_name": "日期",     "type": 5, "property": ["date_formatter": "yyyy/MM/dd HH:mm", "auto_fill": false]],
            ["field_name": "备注",     "type": 1],
            ["field_name": "记账成员", "type": 1],
        ]

        // 并发创建所有字段，比串行快 4-5 倍
        try await withThrowingTaskGroup(of: Void.self) { group in
            for fieldDef in fieldDefs {
                group.addTask {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: fieldDef)
                    _ = try await URLSession.shared.data(for: request)
                }
            }
            try await group.waitForAll()
        }
    }

    private func setPublicEditPermission(token: String, appToken: String) async throws {
        guard let url = URL(string: "https://open.feishu.cn/open-apis/drive/v1/permissions/\(appToken)/public?type=bitable") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "external_access_entity": "open",
            "security_entity":        "anyone_can_edit",
            "comment_entity":         "anyone_can_view",
            "share_entity":           "anyone",
            "link_share_entity":      "tenant_readable",
            "invite_external":        true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: request)
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
