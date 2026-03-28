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
}
