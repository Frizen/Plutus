# Plutus — 消费截屏自动记账

用 iPhone Action Button 一键截屏，GLM Vision 自动识别消费信息，实时写入飞书多维表格。

---

## 功能特性

- 📸 **Action Button 触发**：侧边按钮一按，截屏 + 分析一气呵成
- 🤖 **GLM Vision 识别**：自动提取金额、商户、消费类型、支付渠道、消费时间
- 📊 **飞书 Bitable 写入**：结果实时同步到多维表格，字段名可自定义映射
- 🔔 **轻量通知**：写入成功后显示金额 + 商户，2 秒自动消失
- 📱 **本地历史**：最近 20 条记录随时可查
- 🪵 **运行日志**：App 内实时查看每步执行状态，支持复制

---

## 使用前准备

### 一、GLM API Key

1. 前往 [智谱 AI 开放平台](https://open.bigmodel.cn) → 控制台 → API Keys
2. 创建 API Key
3. 将 Key 填入 App「配置」页

### 二、飞书多维表格

#### 1. 创建飞书自建应用

1. 打开 [飞书开发者后台](https://open.feishu.cn)
2. 点击「创建企业自建应用」，填写名称（如：Plutus）
3. 进入应用 → **权限管理** → 搜索并开启 `bitable:app`
4. 「版本管理与发布」→ 创建版本并发布
5. 记录「基础信息」页面的 **App ID** 和 **App Secret**

#### 2. 创建多维表格

在飞书中新建多维表格，创建以下字段：

| 字段名（默认） | 字段类型 | 说明 |
|----------------|----------|------|
| 金额 | 数字 | 消费金额（人民币）|
| 消费类型 | 单选 | 餐饮/交通/购物/娱乐/医疗/其他 |
| 商户 | 文本 | 商户名称 |
| 支付渠道 | 文本 | 微信/支付宝/京东等 |
| 消费时间 | 日期 | 精确到分钟 |
| 备注 | 文本 | 额外备注 |

> 字段名可在 App「字段名映射」处自定义，与表格实际列名保持一致即可。

从表格 URL 提取配置信息：
```
https://your-domain.feishu.cn/base/[APP_TOKEN]?table=[TABLE_ID]
```

### 三、App 内配置

打开 **Plutus** → 「配置」Tab → 依次填入：

- GLM API Key
- 飞书 App ID / App Secret / Bitable App Token / Table ID
- 按需调整字段名映射

点击「测试飞书连接」验证配置正确。

---

## Action Button 配置

### 步骤一：创建快捷指令

1. 打开「**快捷指令**」App → 右上角 `+` 新建
2. 添加动作 → 搜索「**截屏**」→ 添加
3. 继续添加动作 → 搜索「**记录一笔消费**」（Plutus 提供）
   - 「截图」参数栏默认显示「选择文件」，**不要点它**
   - **长按**截图栏右侧的 **⊕ 图标** → 弹出菜单中选择「**截屏**」变量
   - 参数栏变为蓝色「截屏」标签即表示正确
4. 完成，命名为「**记录消费**」

### 步骤二：绑定 Action Button

**设置 → 操作按钮 → 快捷指令 → 选择「记录消费」**

### 使用方式

长按侧边 **Action Button** → 自动截屏 → GLM 识别 → 写入飞书 → 收到通知 🎉

---

## 项目结构

```
ExpenseCapture/
├── ExpenseCapture/
│   ├── App/
│   │   ├── ExpenseCaptureApp.swift       # @main 入口
│   │   ├── ContentView.swift             # TabView 根视图
│   │   ├── SettingsView.swift            # 配置 Tab（API 设置 + 历史记录）
│   │   └── LogView.swift                 # 日志 Tab
│   ├── Intents/
│   │   └── AnalyzeExpenseIntent.swift    # App Intent（Action Button 触发点）
│   ├── Services/
│   │   ├── GLMVisionService.swift        # GLM Vision API 封装
│   │   └── FeishuBitableService.swift    # 飞书 Bitable API 封装
│   ├── Models/
│   │   └── ExpenseRecord.swift           # 数据模型 + 本地持久化
│   └── Storage/
│       ├── AppSettings.swift             # 用户配置（@AppStorage）
│       └── IntentLogger.swift            # 运行日志（UserDefaults）
└── README.md
```

---

## 技术架构

```
Action Button 长按
   → Shortcuts App（用户预配置）
      → "截屏"（系统动作）
         → "记录一笔消费"（App Intent）
            → GLM glm-4v-flash Vision API（图像识别）
               → 飞书 Bitable API（写入记录）
                  → iOS 本地通知（2 秒后自动消失）
```

**为什么使用 Shortcuts + App Intent？**

iOS 不允许 App 直接截取其他 App 的屏幕，但系统 Shortcuts 可以调用「截屏」并将结果传给 App Intent。这是 Apple 官方支持的合规方案，Action Button 可直接触发 Shortcut。

---

## 验证与测试

### 1. 验证 GLM 连接
配置 Tab → 「测试 GLM 连接」，确认 API Key 有效。

### 2. 验证飞书连接
配置 Tab → 「测试飞书连接」，确认 Token 获取成功。

### 3. 集成测试（不用 Action Button）
1. 打开「快捷指令」App → 找到「记录消费」→ 点击 ▶️ 手动运行
2. 检查：
   - 收到通知（显示金额 + 商户，2 秒消失）✓
   - 飞书表格出现新行 ✓
   - App 历史记录更新 ✓
   - 日志 Tab 可查看每步执行详情 ✓

### 4. Action Button 实测
长按侧边 Action Button → 观察通知 → 查看飞书表格。

---

## 注意事项

- **API Key 安全**：当前使用 `@AppStorage`（UserDefaults）存储，生产环境建议升级为 iOS Keychain
- **Token 刷新**：飞书 `tenant_access_token` 有效期 2 小时，已自动缓存并在过期前 5 分钟刷新
- **图片压缩**：截图自动压缩至最大 1024px / ≤1MB，降低 token 消耗
- **容错逻辑**：金额 + 商户两个核心字段成功提取即写入飞书，其他字段缺失只记 warning 不报错
- **负数金额**：微信/支付宝用「-¥6.9」表示支出，已自动取绝对值处理
- **财付通识别**：银行账单中的「财付通」自动映射为支付渠道「微信」

---

## 依赖

- iOS 17.0+（App Intents 完整支持）
- Xcode 15+
- Swift 5.9+
- 无第三方依赖（纯 Apple 原生 + REST API）

---

## License

MIT
