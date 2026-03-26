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
    var screenshot: IntentFile

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let log = IntentLogger.shared
        log.log("▶️ Intent 启动", level: .info)

        // 1. 读取设置
        let settings = AppSettings()
        guard settings.isGLMConfigured else {
            log.log("GLM API Key 未配置", level: .error)
            return .result(dialog: "❌ 请先在 ExpenseCapture App 中配置 GLM API Key")
        }
        log.log("GLM API Key 已配置 ✓", level: .success)

        // 2. 解码图片
        log.log("正在读取截图...", level: .info)
        let imageData = screenshot.data
        log.log("截图数据大小: \(imageData.count / 1024) KB", level: .debug)

        guard let image = UIImage(data: imageData) else {
            log.log("UIImage 解码失败，数据可能不是有效图片", level: .error)
            return .result(dialog: "❌ 截图解码失败，请确保传入的是图片文件")
        }
        log.log("截图尺寸: \(Int(image.size.width))×\(Int(image.size.height)) pt", level: .debug)

        // 3. 调用 GLM Vision
        log.log("正在调用 GLM Vision API...", level: .info)
        let glmService = GLMVisionService()
        let extraction: ExpenseExtraction
        do {
            extraction = try await glmService.analyze(image: image, apiKey: settings.glmAPIKey)
            log.log("GLM 返回 amount=\(extraction.amount), merchant=\(extraction.merchant), category=\(extraction.category)", level: .debug)
        } catch {
            log.log("GLM 调用失败: \(error.localizedDescription)", level: .error)
            return .result(dialog: "❌ 识别失败: \(error.localizedDescription)")
        }

        // 4. 检查核心字段：amount + merchant 两者都有才继续
        guard extraction.amount != 0 else {
            log.log("amount=0，模型判断截图中无消费信息（merchant=\(extraction.merchant)）", level: .warning)
            return .result(dialog: "ℹ️ 截图中未检测到消费信息")
        }
        guard !extraction.merchant.isEmpty, extraction.merchant != "未知商户" else {
            log.log("merchant 未提取到，跳过写入", level: .warning)
            return .result(dialog: "ℹ️ 无法识别商户名称，请重试")
        }

        // 其他字段缺失时记 warning，不阻断流程
        if extraction.category.isEmpty || extraction.category == "其他" {
            log.log("category 未能精确识别，使用默认值「其他」", level: .warning)
        }
        if extraction.transactionDate == nil {
            log.log("transactionDate 未提取到，将使用当前时间", level: .warning)
        }

        log.log("核心字段就绪: \(extraction.currency)\(extraction.amount) @ \(extraction.merchant)", level: .success)

        // 5. 创建本地记录
        let record = ExpenseRecord(from: extraction)

        // 6. 写入飞书
        if settings.isFeishuConfigured {
            log.log("正在写入飞书 Bitable...", level: .info)
            let feishuService = FeishuBitableService()
            do {
                try await feishuService.addRecord(
                    expense: record,
                    appID: settings.feishuAppID,
                    appSecret: settings.feishuAppSecret,
                    appToken: settings.bitableAppToken,
                    tableID: settings.tableID,
                    fieldNames: FeishuFieldNames(settings: settings)
                )
                log.log("飞书写入成功 ✓", level: .success)
            } catch {
                log.log("飞书写入失败: \(error.localizedDescription)", level: .error)
            }
        } else {
            log.log("飞书未配置，跳过写入", level: .warning)
        }

        // 7. 保存本地
        await saveLocalRecord(record)
        log.log("本地记录已保存", level: .success)

        // 8. 返回结果给快捷指令
        let dialogText = "✅已记账 \(record.displayAmount) \(record.merchant)"
        log.log("▶️ Intent 完成", level: .success)
        return .result(dialog: IntentDialog(stringLiteral: dialogText))
    }

    // MARK: - Helpers

    @MainActor
    private func saveLocalRecord(_ record: ExpenseRecord) {
        let store = ExpenseRecordStore()
        store.add(record)
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
