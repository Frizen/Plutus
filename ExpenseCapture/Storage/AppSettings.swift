import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    // GLM (智谱 AI)
    @AppStorage("glm_api_key") var glmAPIKey: String = ""

    // 飞书自建应用
    @AppStorage("feishu_app_id") var feishuAppID: String = ""
    @AppStorage("feishu_app_secret") var feishuAppSecret: String = ""

    // 飞书多维表格
    @AppStorage("feishu_bitable_app_token") var bitableAppToken: String = ""
    @AppStorage("feishu_table_id") var tableID: String = ""

    // 飞书字段名映射（默认值与 README 一致，用户可按实际表格修改）
    @AppStorage("field_amount")           var fieldAmount: String          = "金额"
    @AppStorage("field_primary_category") var fieldPrimaryCategory: String = "一级分类"
    @AppStorage("field_sub_category")     var fieldSubCategory: String     = "二级分类"
    @AppStorage("field_merchant")         var fieldMerchant: String        = "商户"
    @AppStorage("field_date")             var fieldDate: String            = "消费时间"
    @AppStorage("field_notes")            var fieldNotes: String           = "备注"

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

    /// GLM 已配置即可使用（飞书为可选云同步）
    var isReadyToUse: Bool {
        isGLMConfigured
    }

    var isFullyConfigured: Bool {
        isGLMConfigured && isFeishuConfigured
    }
}
