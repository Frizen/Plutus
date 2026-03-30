import Foundation
import UIKit

// MARK: - Errors

enum GLMVisionError: LocalizedError {
    case apiKeyMissing
    case imageEncodingFailed
    case networkError(Error)
    case invalidResponse(Int, String)
    case decodingFailed(String)
    case noExpenseFound

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing: return "未配置 GLM API Key"
        case .imageEncodingFailed: return "图片编码失败"
        case .networkError(let e): return "网络错误: \(e.localizedDescription)"
        case .invalidResponse(let code, let msg): return "API 返回错误 [\(code)]: \(msg)"
        case .decodingFailed(let msg): return "解析响应失败: \(msg)"
        case .noExpenseFound: return "截图中未发现消费信息"
        }
    }
}

// MARK: - GLM API Models (OpenAI-compatible)

private struct GLMRequest: Encodable {
    let model: String
    let messages: [GLMMessage]
    let max_tokens: Int
    let temperature: Double
}

private struct GLMMessage: Encodable {
    let role: String
    let content: [GLMContent]
}

private struct GLMContent: Encodable {
    let type: String
    let text: String?
    let image_url: GLMImageURL?

    init(text: String) {
        self.type = "text"
        self.text = text
        self.image_url = nil
    }

    init(imageBase64: String) {
        self.type = "image_url"
        self.text = nil
        self.image_url = GLMImageURL(url: "data:image/jpeg;base64,\(imageBase64)")
    }
}

private struct GLMImageURL: Encodable {
    let url: String
}

private struct GLMResponse: Decodable {
    let choices: [GLMChoice]
}

private struct GLMChoice: Decodable {
    let message: GLMResponseMessage
}

private struct GLMResponseMessage: Decodable {
    let content: String
}

// MARK: - Service

class GLMVisionService {

    static let shared = GLMVisionService()

    private let apiEndpoint = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    private let model = "glm-4v-flash"
    private let maxImageDimension: CGFloat = 1024

    // MARK: - Public API

    /// 将图片压缩并编码为 Base64，供 Phase 1 / Phase 2 共用，避免重复编码
    func encodeImage(_ image: UIImage) async throws -> String {
        return try await _encodeImage(image)
    }

    /// Phase 1：只提取金额、商户、交易时间（prompt 精简，速度最快）
    func analyzeCore(imageBase64: String, apiKey: String) async throws -> CoreExtraction {
        let prompt = """
        你是一个消费记录提取助手，从手机截图中提取消费信息。

        识别规则：
        1. 找页面中的消费金额（¥ 符号后的数字，或"实付""合计"等字段）
        2. amount 必须是正数，"-¥6.90"中 "-" 只是支出方向，填 6.9
        3. 仅当截图明确与支付无关（聊天/朋友圈/设置页）时，amount 才填 0
        4. 商户识别优先级：
           【1】圆形 logo 旁紧邻的短文本（最可靠，通常是品牌名）
           【2】金额正上方或正下方的短文本
           【3】"商户名称""收款方""店铺名称""商家"字段后的文本
           【4】订单标题、收款备注
           以上都没有时填"未知商户"
        5. 商户名称应该是品牌名或简称（通常 2-8 个字），不要填工商注册的公司全称（如"广州市××区××饮品店""北京××科技有限公司"等含"市""区""有限公司""科技"等字样的长文本）。若页面同时存在品牌简称和公司全称，优先取品牌简称。
        6. transactionDate 格式为 yyyy-MM-dd HH:mm，精确到分钟，无则为 null

        请严格按照以下 JSON 格式返回，不要有任何其他内容：
        {
          "amount": <正数，若无消费则为0>,
          "merchant": <商户品牌名或简称，不要填公司全称>,
          "transactionDate": <yyyy-MM-dd HH:mm 或 null>
        }
        """
        let text = try await callGLM(imageBase64: imageBase64, prompt: prompt, apiKey: apiKey)
        IntentLogger.shared.log("Phase1 原始回包: \(text.prefix(200))", level: .debug)
        return try parseJSON(from: text, as: CoreExtraction.self)
    }

    /// Phase 2：在已知商户名的基础上，识别二级分类和备注（后台静默执行）
    func analyzeDetail(imageBase64: String, merchant: String, apiKey: String) async throws -> DetailExtraction {
        let prompt = """
        你是一个消费分类助手。商户名称为「\(merchant)」，请结合截图内容识别二级分类和备注。

        二级分类只能从以下选项中选择一个：
        外出就餐、外卖、水果、零食、买菜、奶茶、饮料酒水、物业费、水电燃气、电器、手机话费、
        红包、礼物、地铁公交、长途交通、打车、生活用品、电子数码、美妆护肤、衣裤鞋帽、
        书报杂志、珠宝首饰、宠物、美发、医疗、药物、慈善、娱乐、旅游、按摩、运动、保险

        分类参考：
        - 外出就餐：麦当劳、肯德基、海底捞、西贝、火锅、烧烤、快餐等线下堂食
        - 外卖：美团外卖、饿了么
        - 奶茶：星巴克、瑞幸、喜茶、奈雪、古茗、蜜雪冰城、茶百道
        - 打车：滴滴、T3出行、曹操出行、嘀嗒、出租车
        - 长途交通：高铁、火车、飞机、12306、携程、同程
        - 地铁公交：地铁、公交、城市轨道
        - 娱乐：电影、KTV、游戏、演唱会、视频/音乐会员、Steam
        - 旅游：酒店、民宿、景区
        无法判断时填「其他」

        请严格按照以下 JSON 格式返回，不要有任何其他内容：
        {
          "subCategory": <二级分类>,
          "notes": <备注，无则为 null>
        }
        """
        let text = try await callGLM(imageBase64: imageBase64, prompt: prompt, apiKey: apiKey)
        IntentLogger.shared.log("Phase2 原始回包: \(text.prefix(200))", level: .debug)
        return try parseJSON(from: text, as: DetailExtraction.self)
    }

    // MARK: - Shared Helpers

    private func _encodeImage(_ image: UIImage) async throws -> String {
        return try await Task.detached(priority: .userInitiated) {
            let resized = self.resizeImage(image, maxDimension: self.maxImageDimension)
            guard let data = resized.jpegData(compressionQuality: 0.85) else {
                throw GLMVisionError.imageEncodingFailed
            }
            let finalData: Data
            if data.count > 1_000_000 {
                guard let compressed = resized.jpegData(compressionQuality: 0.5) else {
                    throw GLMVisionError.imageEncodingFailed
                }
                finalData = compressed
            } else {
                finalData = data
            }
            return finalData.base64EncodedString()
        }.value
    }

    private func callGLM(imageBase64: String, prompt: String, apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GLMVisionError.apiKeyMissing
        }

        let requestBody = GLMRequest(
            model: model,
            messages: [
                GLMMessage(role: "user", content: [
                    GLMContent(imageBase64: imageBase64),
                    GLMContent(text: prompt)
                ])
            ],
            max_tokens: 256,
            temperature: 0.1
        )

        guard let url = URL(string: apiEndpoint) else {
            throw GLMVisionError.decodingFailed("API 端点格式错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GLMVisionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GLMVisionError.decodingFailed("非 HTTP 响应")
        }
        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "无响应体"
            IntentLogger.shared.log("HTTP \(httpResponse.statusCode): \(bodyStr.prefix(200))", level: .error)
            throw GLMVisionError.invalidResponse(httpResponse.statusCode, bodyStr)
        }

        let glmResponse = try JSONDecoder().decode(GLMResponse.self, from: data)
        guard let text = glmResponse.choices.first?.message.content else {
            throw GLMVisionError.decodingFailed("响应中无文本内容")
        }
        return text
    }

    private func parseJSON<T: Decodable>(from text: String, as type: T.Type) throws -> T {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 剥除 markdown 代码块
        if let range = jsonString.range(of: "```json") {
            jsonString = String(jsonString[range.upperBound...])
            if let end = jsonString.range(of: "```") {
                jsonString = String(jsonString[..<end.lowerBound])
            }
        } else if let range = jsonString.range(of: "```") {
            jsonString = String(jsonString[range.upperBound...])
            if let end = jsonString.range(of: "```") {
                jsonString = String(jsonString[..<end.lowerBound])
            }
        }

        // 2. 用括号计数法提取最外层 JSON 对象，避免 notes 字段含 {} 时截断错误
        if let extracted = extractOutermostObject(from: jsonString) {
            jsonString = extracted
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GLMVisionError.decodingFailed("无法将文本转为 Data")
        }

        do {
            return try JSONDecoder().decode(type, from: jsonData)
        } catch {
            throw GLMVisionError.decodingFailed("JSON 解析失败: \(error.localizedDescription)\n原始: \(text.prefix(300))")
        }
    }

    /// 用括号计数法找到字符串中第一个完整的 JSON 对象 `{ ... }`，
    /// 正确处理嵌套括号和字符串内的括号字符。
    func extractOutermostObject(from text: String) -> String? {
        var depth = 0
        var startIndex: String.Index? = nil
        var inString = false
        var escaped = false

        for idx in text.indices {
            let ch = text[idx]
            if escaped { escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }

            if ch == "{" {
                if depth == 0 { startIndex = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start = startIndex {
                    return String(text[start...idx])
                }
            }
        }
        return nil
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
