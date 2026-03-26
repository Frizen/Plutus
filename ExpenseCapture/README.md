# ExpenseCapture — 消费截屏自动记账

用 iPhone Action Button 一键截屏，自动识别消费金额、商户、类型，并写入飞书多维表格。

---

## 功能特性

- 📸 **Action Button 触发**：侧边按钮一按，截屏 + 分析一气呵成
- 🤖 **Claude Vision 识别**：自动提取金额、货币、商户、消费类型
- 📊 **飞书 Bitable 写入**：结果实时同步到你的多维表格
- 🔔 **即时通知**：识别完成后推送通知展示结果
- 📱 **本地历史**：最近 20 条记录随时可查

---

## 使用前准备

### 一、Claude API Key

1. 前往 [Anthropic Console](https://console.anthropic.com) → API Keys
2. 创建 API Key（以 `sk-ant-` 开头）
3. 将 Key 填入 App 设置页

### 二、飞书多维表格（前置配置）

#### 1. 创建飞书自建应用

1. 打开 [飞书开发者后台](https://open.feishu.cn)
2. 点击「创建企业自建应用」，填写名称（如：消费记账）
3. 进入应用 → **权限管理** → 搜索并开启：
   - `bitable:app`（多维表格读写）
4. 点击「版本管理与发布」→ 创建版本并发布（或申请发布）
5. 记录「基础信息」页面的 **App ID** 和 **App Secret**

#### 2. 创建多维表格

1. 在飞书中新建一个**多维表格**
2. 在表格中创建以下字段（字段名必须与此完全一致）：

| 字段名 | 字段类型 | 说明 |
|--------|----------|------|
| 金额 | 数字 | 消费金额 |
| 货币 | 文本 | CNY/USD 等 |
| 消费类型 | 单选 | 餐饮/交通/购物/娱乐/医疗/其他 |
| 商户 | 文本 | 商户名称 |
| 日期 | 文本 | 交易时间 |
| 备注 | 文本 | 额外备注 |
| 截图来源 | 文本 | 自动填入 "iPhone Action Button" |

3. 从表格 URL 中提取信息：
   ```
   https://your-domain.feishu.cn/base/[APP_TOKEN]?table=[TABLE_ID]
   ```
   - `APP_TOKEN`：URL 中 `/base/` 后面的部分
   - `TABLE_ID`：`?table=` 后面的部分（以 `tbl` 开头）

### 三、App 内配置

打开 **ExpenseCapture App** → 填入：
- Claude API Key
- 飞书 App ID / App Secret
- Bitable App Token
- Table ID

点击「测试飞书连接」验证配置正确。

---

## Action Button 配置

### 步骤一：创建快捷指令

1. 打开 iPhone 上的「**快捷指令**」App
2. 点击右上角 `+` 新建快捷指令
3. 添加动作 → 搜索「**截屏**」→ 选择「截屏」
4. 继续添加动作 → 搜索「**记录一笔消费**」（ExpenseCapture 提供）
   - 此时「截图」参数栏默认显示「选择文件」，**不要点它**
   - **长按**截图栏右侧的 **⊕ 图标** → 在弹出菜单中选择「**截屏**」
   - 参数栏变为蓝色的「截屏」标签即表示设置正确
5. 点击右上角完成，将快捷指令命名为「**记录消费**」

### 步骤二：绑定 Action Button

1. 打开「**设置**」→ **操作按钮**（Action Button）
2. 滑动选择「**快捷指令**」
3. 点击下方选择快捷指令 → 选择「**记录消费**」
4. 完成 ✓

### 使用方式

长按侧边 **Action Button** → 自动截屏 → AI 识别消费 → 写入飞书 → 收到通知 🎉

---

## 项目结构

```
ExpenseCapture/
├── ExpenseCapture/
│   ├── App/
│   │   ├── ExpenseCaptureApp.swift       # @main 入口
│   │   └── ContentView.swift             # 设置页 + 历史记录
│   ├── Intents/
│   │   └── AnalyzeExpenseIntent.swift    # App Intent（Action Button 触发点）
│   ├── Services/
│   │   ├── ClaudeVisionService.swift     # Claude Vision API
│   │   └── FeishuBitableService.swift    # 飞书 Bitable API
│   ├── Models/
│   │   └── ExpenseRecord.swift           # 数据模型 + 本地持久化
│   └── Storage/
│       └── AppSettings.swift             # 用户配置（@AppStorage）
└── README.md
```

---

## 技术架构

```
Action Button 长按
   → Shortcuts App（用户预配置）
      → "截屏"（系统动作）
         → "记录一笔消费"（App Intent）
            → Claude Vision API（图像识别）
               → 飞书 Bitable API（写入记录）
                  → iOS 通知（展示结果）
```

**为什么使用 Shortcuts + App Intent？**

iOS 不允许 App 直接截取其他 App 的屏幕，但系统 Shortcuts 可以调用「截屏」并将结果传给 App Intent。这是 Apple 官方支持的合规方案，Action Button 可直接触发 Shortcut。

---

## 验证与测试

### 1. 验证 Claude API
在 App 设置页点击「测试 Claude 连接」，检查 API Key 格式。

### 2. 验证飞书连接
在 App 设置页点击「测试飞书连接」，确认 Token 获取成功。

### 3. 集成测试（不用 Action Button）
1. 打开「快捷指令」App
2. 找到「记录消费」快捷指令
3. 点击▶️ 手动运行
4. 检查：
   - 手机收到通知 ✓
   - 飞书表格出现新行 ✓
   - App 历史记录更新 ✓

### 4. Action Button 测试
长按侧边 Action Button → 观察通知 → 查看飞书表格。

---

## 注意事项

- **API Key 安全**：当前使用 `@AppStorage`（UserDefaults）存储，生产环境建议升级为 iOS Keychain
- **Token 刷新**：飞书 `tenant_access_token` 有效期 2 小时，服务已自动缓存并在过期前 5 分钟刷新
- **图片压缩**：截图会自动压缩至最大 1024px，JPEG 质量 85%（≤1MB），降低 Token 消耗
- **离线场景**：无网络时 Intent 会失败并推送错误通知，记录不会丢失
- **飞书字段名**：字段名必须与表格中完全一致（区分中英文和空格）

---

## 依赖

- iOS 17.0+（App Intents 完整支持）
- Xcode 15+
- Swift 5.9+
- 无第三方依赖（纯 Apple 原生 + REST API）

---

## License

MIT
