import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    // GLM (智谱 AI)
    @AppStorage("glm_api_key") var glmAPIKey: String = ""

    // 记账成员
    @AppStorage("user_name") var userName: String = ""

    // 飞书同步开关
    @AppStorage("feishu_sync_enabled") var feishuSyncEnabled: Bool = false

    // 飞书自建应用
    @AppStorage("feishu_app_id") var feishuAppID: String = ""
    @AppStorage("feishu_app_secret") var feishuAppSecret: String = ""

    /// 当前使用的是内置测试飞书应用（凭证不对用户展示）
    var isUsingTestFeishuCredentials: Bool {
        feishuAppID == "cli_a94fae2862ba9bc6"
    }

    // 飞书多维表格
    @AppStorage("feishu_bitable_app_token") var bitableAppToken: String = ""
    @AppStorage("feishu_table_id") var tableID: String = ""

    // 飞书字段名映射
    @AppStorage("field_amount")    var fieldAmount:    String = "金额"
    @AppStorage("field_merchant")  var fieldMerchant:  String = "商户"
    @AppStorage("field_date")      var fieldDate:      String = "日期"
    @AppStorage("field_notes")     var fieldNotes:     String = "备注"
    @AppStorage("field_user_name") var fieldUserName:  String = "记账成员"

    // 验证配置完整性
    var isGLMConfigured: Bool {
        !glmAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isFeishuConfigured: Bool {
        !feishuAppID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !feishuAppSecret.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bitableAppToken.trimmingCharacters(in: .whitespaces).isEmpty &&
        !tableID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 飞书同步开关已开启且配置完整
    var isFeishuSyncActive: Bool {
        feishuSyncEnabled && isFeishuConfigured
    }

    /// GLM 已配置即可使用（飞书为可选云同步）
    var isReadyToUse: Bool {
        isGLMConfigured
    }

    var isFullyConfigured: Bool {
        isGLMConfigured && isFeishuSyncActive
    }

    // MARK: - Bitable URL Parsing

    /// 从飞书多维表格链接解析 appToken 和 tableID，写入对应属性。
    /// 返回解析结果描述，供 UI 展示。
    @discardableResult
    func parseBitableURL(_ urlString: String) -> (success: Bool, message: String)? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed),
              let host = url.host,
              host.contains("feishu.cn") || host.contains("larkoffice.com") else {
            return (false, "链接格式不正确，需为飞书多维表格链接")
        }
        let pathComponents = url.pathComponents
        guard let baseIndex = pathComponents.firstIndex(of: "base"),
              baseIndex + 1 < pathComponents.count else {
            return (false, "未找到 /base/ 路径，请确认是多维表格链接")
        }
        let appToken = pathComponents[baseIndex + 1]
        guard !appToken.isEmpty else {
            return (false, "未找到 App Token")
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let tableID = components?.queryItems?.first(where: { $0.name == "table" })?.value ?? ""
        bitableAppToken = appToken
        if tableID.isEmpty {
            self.tableID = ""
            return (false, "链接中缺少 Table ID 参数，请在浏览器打开后重新复制")
        } else {
            self.tableID = tableID
            return (true, "解析成功 ✓")
        }
    }
}
