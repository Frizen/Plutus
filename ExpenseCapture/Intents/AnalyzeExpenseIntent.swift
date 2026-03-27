import AppIntents
import UIKit

// MARK: - App Intent

struct AnalyzeExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记录一笔消费"
    static var description: IntentDescription = IntentDescription(
        "截屏后自动分析消费信息并写入飞书多维表格",
        categoryName: "消费记账"
    )

    @Parameter(title: "截图")
    var screenshot: IntentFile?

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let log = IntentLogger.shared
        log.log("▶️ Intent 启动", level: .info)

        // 1. 读取设置
        let settings = AppSettings()
        guard settings.isGLMConfigured else {
            log.log("GLM API Key 未配置", level: .error)
            return .result(dialog: "❌ 请先在 Plutus App 中配置 GLM API Key")
        }

        // 2. 解码图片
        guard let screenshotFile = screenshot else {
            log.log("未收到截图，请在快捷指令中连接「截屏」动作", level: .error)
            return .result(dialog: "❌ 未收到截图，请确保快捷指令中已添加「截屏」动作并连接到本步骤")
        }
        log.log("正在读取截图...", level: .info)
        let imageData = screenshotFile.data
        log.log("截图数据大小: \(imageData.count / 1024) KB", level: .debug)

        guard let image = UIImage(data: imageData) else {
            log.log("UIImage 解码失败", level: .error)
            return .result(dialog: "❌ 截图解码失败，请确保传入的是图片文件")
        }
        log.log("截图尺寸: \(Int(image.size.width))×\(Int(image.size.height)) pt", level: .debug)

        // 3. Phase 1：识别核心字段（金额、商户、时间）
        log.log("Phase1：识别核心字段...", level: .info)
        let glmService = GLMVisionService()
        let core: CoreExtraction
        do {
            core = try await glmService.analyzeCore(image: image, apiKey: settings.glmAPIKey)
            log.log("Phase1 完成: amount=\(core.amount), merchant=\(core.merchant)", level: .debug)
        } catch {
            log.log("Phase1 失败: \(error.localizedDescription)", level: .error)
            return .result(dialog: "❌ 识别失败: \(error.localizedDescription)")
        }

        // 4. 校验核心字段
        guard core.amount != 0 else {
            log.log("amount=0，截图中无消费信息", level: .warning)
            return .result(dialog: "ℹ️ 截图中未检测到消费信息")
        }
        guard !core.merchant.isEmpty, core.merchant != "未知商户" else {
            log.log("merchant 未提取到，跳过写入", level: .warning)
            return .result(dialog: "ℹ️ 无法识别商户名称，请重试")
        }
        if core.transactionDate == nil {
            log.log("transactionDate 未提取到，将使用当前时间", level: .warning)
        }

        // 5. 创建本地记录（分类暂为「其他」，Phase2 补全）
        let record = ExpenseRecord(from: core)
        log.log("核心字段就绪: \(record.displayAmount) @ \(record.merchant)", level: .success)

        // 6. Phase1 写入飞书（只写金额、商户、时间）
        var feishuRecordID: String? = nil
        if settings.isFeishuConfigured {
            log.log("Phase1 写入飞书...", level: .info)
            let feishuService = FeishuBitableService()
            do {
                feishuRecordID = try await feishuService.addRecord(
                    expense: record,
                    appID: settings.feishuAppID,
                    appSecret: settings.feishuAppSecret,
                    appToken: settings.bitableAppToken,
                    tableID: settings.tableID,
                    fieldNames: FeishuFieldNames(settings: settings)
                )
                log.log("Phase1 飞书写入成功 ✓ recordID=\(feishuRecordID ?? "-")", level: .success)
            } catch {
                log.log("Phase1 飞书写入失败: \(error.localizedDescription)", level: .error)
            }
        } else {
            log.log("飞书未配置，跳过写入", level: .warning)
        }

        // 7. 保存本地（先以「其他」占位）
        await saveLocalRecord(record)
        log.log("本地记录已保存（Phase1）", level: .success)

        // 8. 返回 dialog（Phase1 完成，用户已感知结果）
        let modeTag = settings.isFeishuConfigured ? "" : "（仅本地）"
        let dialogText = "✅已记账\(modeTag) \(record.displayAmount) \(record.merchant)"
        log.log("▶️ Phase1 完成，返回 dialog", level: .success)

        // 9. Phase2：后台静默识别分类和备注
        let recordID = record.id
        let feishuID = feishuRecordID
        let apiKey = settings.glmAPIKey
        let merchant = record.merchant

        Task {
            log.log("Phase2：后台识别分类...", level: .info)
            do {
                let detail = try await glmService.analyzeDetail(image: image, merchant: merchant, apiKey: apiKey)
                log.log("Phase2 完成: subCategory=\(detail.subCategory)", level: .debug)

                // 更新本地记录
                await updateLocalRecord(id: recordID, with: detail)
                log.log("Phase2 本地记录已更新", level: .success)

                // PATCH 飞书
                if settings.isFeishuConfigured, let fid = feishuID {
                    let feishuService = FeishuBitableService()
                    do {
                        try await feishuService.updateRecord(
                            recordID: fid,
                            detail: detail,
                            appID: settings.feishuAppID,
                            appSecret: settings.feishuAppSecret,
                            appToken: settings.bitableAppToken,
                            tableID: settings.tableID,
                            fieldNames: FeishuFieldNames(settings: settings)
                        )
                        log.log("Phase2 飞书更新成功 ✓", level: .success)
                    } catch {
                        log.log("Phase2 飞书更新失败: \(error.localizedDescription)", level: .error)
                    }
                }
            } catch {
                log.log("Phase2 识别失败: \(error.localizedDescription)", level: .error)
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogText))
    }

    // MARK: - Helpers

    @MainActor
    private func saveLocalRecord(_ record: ExpenseRecord) {
        let store = ExpenseRecordStore()
        store.add(record)
    }

    @MainActor
    private func updateLocalRecord(id: UUID, with detail: DetailExtraction) {
        let store = ExpenseRecordStore()
        store.update(id: id, with: detail)
    }
}

// MARK: - App Shortcuts Provider

struct ExpenseCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AnalyzeExpenseIntent(),
            phrases: [
                "用 \(.applicationName) 记录消费",
                "\(.applicationName) 记录一笔消费",
                "用 \(.applicationName) 分析消费截图"
            ],
            shortTitle: "记录消费",
            systemImageName: "camera.viewfinder"
        )
    }
}
