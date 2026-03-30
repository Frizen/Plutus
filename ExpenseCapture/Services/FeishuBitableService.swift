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
        case .configMissing:
            return "飞书配置不完整，请在配置页补充 App ID / Secret / 表格信息"
        case .tokenFetchFailed(let msg):
            // 解析飞书内部错误码，给出更具体的提示
            if msg.contains("99991668") || msg.contains("99991663") || msg.contains("10003") {
                return "飞书 App ID 或 Secret 不正确，请检查配置"
            } else if msg.contains("99991664") {
                return "飞书应用已被停用，请检查飞书后台"
            }
            return "飞书授权失败，请确认 App ID 和 App Secret 填写正确"
        case .networkError:
            return "网络连接失败，请检查网络后重试"
        case .invalidResponse(let code, _):
            switch code {
            case 403:
                return "没有访问权限，请确认飞书应用已开启相关权限"
            case 429:
                return "请求过于频繁，请稍后再试"
            case 401:
                return "飞书授权已过期，请重新配置"
            case 500, 502, 503:
                return "飞书服务暂时不可用，请稍后重试"
            default:
                return "飞书同步失败（错误 \(code)），请稍后重试"
            }
        case .encodingFailed:
            return "请求编码失败，请重试"
        case .decodingFailed:
            return "飞书返回数据格式异常，请稍后重试"
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

    // MARK: 超时常量
    private let tokenTimeout: TimeInterval = 15   // Token 请求（轻量）
    private let recordTimeout: TimeInterval = 20  // 记录读写 / 建表等操作

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
        request.timeoutInterval = tokenTimeout

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
        request.timeoutInterval = recordTimeout

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

    /// 从模板复制一个新的多维表格，并开放「互联网所有人可编辑」权限。
    /// 返回 (appToken, tableID)，权限设置失败时静默忽略。
    func createExpenseBitable(appID: String, appSecret: String) async throws -> (appToken: String, tableID: String) {
        let token      = try await fetchFreshToken(appID: appID, appSecret: appSecret)
        let folderToken = try await getRootFolderToken(token: token)
        let appToken   = try await copyBitableFromTemplate(token: token, folderToken: folderToken)
        let tableID    = try await getFirstTableID(token: token, appToken: appToken)
        try? await setPublicEditPermission(token: token, appToken: appToken)
        return (appToken, tableID)
    }

    /// 获取应用在飞书云空间的根目录 token，用于指定复制文件的目标位置。
    private func getRootFolderToken(token: String) async throws -> String {
        let url = URL(string: "https://open.feishu.cn/open-apis/drive/explorer/v2/root_folder/meta")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = recordTimeout

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = json?["code"] as? Int, code == 0,
              let dataObj = json?["data"] as? [String: Any],
              let folderToken = dataObj["token"] as? String else {
            let msg = (json?["msg"] as? String) ?? "解析失败"
            throw FeishuError.invalidResponse(-1, "获取根目录失败: \(msg)")
        }
        return folderToken
    }

    /// 从固定模板复制一份新的多维表格，返回新表格的 appToken。
    private func copyBitableFromTemplate(token: String, folderToken: String) async throws -> String {
        // 模板表格：https://i7zbvqw45v.feishu.cn/base/YJY0b3H6BagPM1sDj7Vcy7mGnOf
        let templateToken = "YJY0b3H6BagPM1sDj7Vcy7mGnOf"
        let url = URL(string: "https://open.feishu.cn/open-apis/drive/v1/files/\(templateToken)/copy")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name":         "Plutus 记账",
            "type":         "bitable",
            "folder_token": folderToken
        ])
        request.timeoutInterval = recordTimeout

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = json?["code"] as? Int, code == 0,
              let dataObj = json?["data"] as? [String: Any],
              let file = dataObj["file"] as? [String: Any],
              let newToken = file["token"] as? String else {
            let msg = (json?["msg"] as? String) ?? "解析失败"
            throw FeishuError.invalidResponse(-1, "复制模板失败: \(msg)")
        }
        return newToken
    }

    private func getFirstTableID(token: String, appToken: String) async throws -> String {
        // 复制模板后后端异步初始化，items 可能暂时为空。
        // 最多重试 8 次，每次间隔 1.5s（总等待上限约 10.5s）。
        let url = URL(string: "\(bitableEndpoint)/\(appToken)/tables")!
        var lastError: Error = FeishuError.decodingFailed("无法获取 Table ID")

        for attempt in 1...8 {
            if attempt > 1 {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = recordTimeout

            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let code = json?["code"] as? Int, code == 0,
               let dataObj = json?["data"] as? [String: Any],
               let items = dataObj["items"] as? [[String: Any]],
               let first = items.first,
               let tableID = first["table_id"] as? String {
                return tableID
            }
            let rawMsg = (json?["msg"] as? String) ?? (String(data: data, encoding: .utf8) ?? "空响应")
            IntentLogger.shared.log("getFirstTableID 尝试 \(attempt)/8 未就绪：\(rawMsg)", level: .warning)
            lastError = FeishuError.decodingFailed("无法获取 Table ID（尝试 \(attempt)/8）")
        }
        throw lastError
    }

    private func setPublicEditPermission(token: String, appToken: String) async throws {
        guard let url = URL(string: "https://open.feishu.cn/open-apis/drive/v1/permissions/\(appToken)/public?type=bitable") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = recordTimeout
        let body: [String: Any] = [
            "external_access_entity": "open",
            "security_entity":        "anyone_can_edit",
            "comment_entity":         "anyone_can_view",
            "share_entity":           "anyone",
            "link_share_entity":      "anyone_editable",
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
