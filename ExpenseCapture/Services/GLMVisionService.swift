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

    private let apiEndpoint = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    private let model = "glm-4v-flash"
    private let maxImageDimension: CGFloat = 1024

    // MARK: - Public API

    func analyze(image: UIImage, apiKey: String) async throws -> ExpenseExtraction {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GLMVisionError.apiKeyMissing
        }

        let resizedImage = resizeImage(image, maxDimension: maxImageDimension)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.85) else {
            throw GLMVisionError.imageEncodingFailed
        }

        let base64String: String
        if imageData.count > 1_000_000 {
            guard let compressedData = resizedImage.jpegData(compressionQuality: 0.5) else {
                throw GLMVisionError.imageEncodingFailed
            }
            base64String = compressedData.base64EncodedString()
        } else {
            base64String = imageData.base64EncodedString()
        }

        return try await callGLMAPI(imageBase64: base64String, apiKey: apiKey)
    }

    // MARK: - Private

    private func callGLMAPI(imageBase64: String, apiKey: String) async throws -> ExpenseExtraction {
        let prompt = """
        你是一个消费记录提取助手，从手机截图中提取消费信息。
        截图来源包括但不限于：微信支付详情、支付宝账单、美团订单、滴滴行程、京东/淘宝订单、银行转账记录、各类收银小票等。

        识别规则：
        1. 微信支付：找"¥"金额、收款方/商户名称、交易时间（页面上方或底部）
        2. 支付宝：找"实付款"或"¥"金额、商家名称、交易时间
        3. 外卖/电商：找"实付"或"合计"金额、店铺名称、下单时间
        4. 只要页面中出现了金额数字和收款对象，就判定为消费信息，amount 填入金额数字
        5. 仅当截图明确是聊天、朋友圈、设置页等与支付完全无关的页面时，才将 amount 设为 0
        6. amount 必须是正数。微信/支付宝等 App 用"-¥6.90"表示支出，"-"只是方向标记，amount 应填 6.9，不要填负数

        消费类型判断规则（优先根据商户名推断，再结合页面内容）：
        - 餐饮：餐厅、饭店、咖啡、奶茶、外卖、烧烤、火锅、快餐、食堂、面包、蛋糕、甜品、便利店、超市食品区，以及品牌如：麦当劳、肯德基、星巴克、瑞幸、喜茶、奈雪、蜜雪冰城、古茗、茶百道、沪上阿姨、一点点、海底捞、西贝、太二、美团外卖、饿了么
        - 交通：滴滴、出租车、高铁、火车、飞机、机票、地铁、公交、加油站、ETC、停车、顺风车、曹操出行、嘀嗒、T3出行、12306
        - 购物：淘宝、天猫、京东、拼多多、抖音商城、唯品会、得物、SHEIN、超市、商场、便利店（非食品）、服装、电器
        - 娱乐：电影、KTV、游戏、演唱会、景区、剧本杀、密室、视频会员、音乐会员、Steam
        - 医疗：医院、药店、诊所、体检、药品、医保
        - 其他：无法归入以上类别时才选「其他」

        支付渠道判断规则（根据截图的 App 界面风格、顶部导航栏、页面元素判断）：
        - 微信：页面顶部显示"微信支付"/"转账"/"收付款"，绿色主题，或收款方显示微信头像/昵称；若页面出现"财付通"字样也判定为微信
        - 支付宝：页面显示"支付宝"字样，蓝色主题，或"芝麻信用"/"花呗"/"余额宝"等
        - 美团：页面含"美团"字样、黄色主题，或外卖/到店订单
        - 饿了么：蓝色主题外卖订单，含"饿了么"字样
        - 京东：页面含"京东"字样，红色主题，或"京东金融"/"白条"
        - 淘宝/天猫：页面含"淘宝"/"天猫"字样，橙色主题
        - 拼多多：页面含"拼多多"字样
        - 抖音：页面含"抖音"/"抖音商城"字样
        - 携程：页面含"携程"字样
        - 同程：页面含"同程"字样
        - 滴滴：页面含"滴滴"字样，橙色主题
        - 无法判断时填"未知"

        请严格按照以下 JSON 格式返回，不要包含任何其他文字或 markdown 标记：
        {
          "amount": <正数，消费金额，若无则为0>,
          "currency": <货币代码，如 CNY/USD/EUR，默认 CNY>,
          "category": <消费类型，只能是：餐饮/交通/购物/娱乐/医疗/其他 之一>,
          "merchant": <商户名称，如无则为"未知商户">,
          "paymentChannel": <支付渠道，如：微信/支付宝/京东/美团/饿了么/淘宝/天猫/拼多多/抖音/携程/同程/滴滴/未知>,
          "transactionDate": <消费时间字符串，格式为 yyyy-MM-dd HH:mm，必须精确到时和分，如无则为null>,
          "notes": <备注信息，如无则为null>
        }
        只返回 JSON，不要有任何其他内容。
        """

        let requestBody = GLMRequest(
            model: model,
            messages: [
                GLMMessage(role: "user", content: [
                    GLMContent(imageBase64: imageBase64),
                    GLMContent(text: prompt)
                ])
            ],
            max_tokens: 1024,
            temperature: 0.1
        )

        var request = URLRequest(url: URL(string: apiEndpoint)!)
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
            IntentLogger.shared.log("GLM 响应中 choices 为空", level: .error)
            throw GLMVisionError.decodingFailed("响应中无文本内容")
        }

        IntentLogger.shared.log("GLM 原始回包: \(text.prefix(300))", level: .debug)
        return try parseExpenseJSON(from: text)
    }

    private func parseExpenseJSON(from text: String) throws -> ExpenseExtraction {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉可能存在的 ```json ... ``` 包裹
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

        // 提取第一个完整的 JSON 对象
        if let start = jsonString.firstIndex(of: "{"),
           let end = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[start...end])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GLMVisionError.decodingFailed("无法将文本转为 Data")
        }

        do {
            return try JSONDecoder().decode(ExpenseExtraction.self, from: jsonData)
        } catch {
            throw GLMVisionError.decodingFailed("JSON 解析失败: \(error.localizedDescription)\n原始: \(text.prefix(300))")
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
