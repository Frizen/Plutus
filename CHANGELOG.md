# Plutus 产品迭代详情

## v0.26.0 — Code review 修复
**日期**：2026-03

### 变更内容
- `parseBitableURL` 从 `SettingsView` / `SetupWizardView` 提取到 `AppSettings` 扩展，两处共享同一实现，消除重复代码
- 测试飞书凭证保护：`AppSettings` 新增 `isUsingTestFeishuCredentials`，配置页在使用测试应用时隐藏 App ID / Secret 输入框，改为「当前使用内置测试飞书应用」提示
- 修复 GLM 连接校验：`handleNext()` 中 `response as? HTTPURLResponse` 失败时不再静默返回，改为显示「无法获取服务器响应」错误
- 导航动画时长提取为 `pushDuration` / `popDuration` 常量，`DispatchQueue.asyncAfter` 延迟与之对齐，消除硬编码耦合
- 屏幕宽度改用 `GeometryReader` 获取，移除已在 iOS 16 废弃的 `UIScreen.main.bounds.width`
- SF Symbol 图标从 `.resizable().frame()` 改为 `.font(.system(size: 64))`，尺寸渲染更稳定
- `WizardPageContainer` 底部按钮区添加 `Divider`，防止内容较长时视觉混淆
- `advance()` 加 `private` 修饰符，与其他方法保持一致
- 合并 v0.23–v0.25 散碎版本，CHANGELOG 按 commit 粒度整理

---

## v0.25.0 — 配置向导（Setup Wizard）
**日期**：2026-03

### 变更内容
- 新增首次启动配置向导：5 步全屏向导（欢迎 / GLM Key / 飞书同步 / 记账成员名 / Action Button），应用初次安装后自动弹出，显著降低上手门槛
- GLM 页：「测试 Key / 自有 Key」二选一，自有 Key 点「下一步」时自动验证，测试 Key 静默写入不暴露
- 飞书页：「一键创建测试表格 / 自有多维表格」，测试表格自动建字段并开放公共编辑权限；飞书未开启时跳过「记账成员名」页
- Action Button 页：提供 iCloud 快捷指令分享链接，一键添加；配置 Tab 引导同步更新
- 导航采用自定义 ZStack + DragGesture：全屏右滑返回，内容区随手指平移，背后页视差跟随，进度点固定不动
- `FeishuBitableService` 新增 `createExpenseBitable()`，并发建字段（`withThrowingTaskGroup`），`getFirstTableID` 加 3 次重试

---

## v0.22.0 — 记账用户字段
**日期**：2026-03

### 变更内容
- 新增「记账用户」字段：在配置页「通用」区块填写用户名，记账时自动附带到每条记录
- 导出 CSV 新增「记账用户」列
- 旧版本本地记录向后兼容，`userName` 解码失败时默认为空字符串

---

## v0.21.0 — 记录页导出 CSV & 存储上限提升
**日期**：2026-03

### 变更内容
- **导出 CSV**：记录页右上角新增导出按钮，点击后通过系统分享面板导出所有本地记录为 CSV 文件（含日期、金额、商户、分类、备注）
- **存储上限提升**：本地记录最大存储条数从 100 条提升至 1000 条，列表展示不再截断
- **飞书跳转条件收紧**：仅在「同步到飞书多维表格」开关开启且表格链接已成功解析（App Token + Table ID 均存在）时，才在记录页显示跳转飞书的按钮

---

## v0.20.0 — Code Review 修复
**日期**：2026-03

### 变更内容
- **修复本地记录多实例不同步**：`ExpenseRecordStore` 改为单例（`static let shared`），Intent、RecordsView、SettingsView 均引用同一实例，Phase 2 更新分类后无需手动 reload 即可实时反映
- **修复 `IntentLogger` 数据竞争**：`loadEntries()` 改为通过 `queue.sync` 执行，内部读写均在同一串行队列，消除并发读写冲突；`clear()` 也改为 `queue.async`
- **修复 `ExpenseRecord` 字段改名兼容性**：新增 `CodingKeys`，将 `category` 属性的 JSON key 保持为 `subCategory`，旧版本本地存储可正常解码，历史记录不丢失
- **修复 `FeishuBitableService` token 缓存失效**：改为单例，token 在多次调用间复用，不再每次新建实例导致缓存失效
- **删除死代码 `patchRecord` / `updateRecord`**：Phase 2 不写飞书后这两个方法无调用方，一并移除
- **修复 `RecordsView` 飞书跳转链接强制解包**：改为安全解包，链接无效时不显示按钮
- **修复 `DateFormatter` 重复创建**：`LogEntry.timeString` 的 `DateFormatter` 改为 `static let`，避免列表滚动时频繁初始化
- **修正 Intent 步骤注释编号**：原来第二个「5.」之后编号都错了一位，已修正

---

## v0.19.0 — 飞书同步开关 & 分类体系简化
**日期**：2026-03

### 变更内容
- **飞书同步开关**：配置页新增开关，关闭时隐藏所有飞书配置项（连接配置、字段名映射），数据仅保存本地；开启时才展示并写入飞书
- **去掉一级分类**：移除一级分类字段，`ExpenseRecord` 和飞书字段名映射均不再涉及一级分类
- **二级分类改名为「分类」**：`ExpenseRecord.subCategory` 重命名为 `category`，记录列表展示格式更新为「分类 · 时间」
- **Phase 2 恢复并调整**：Phase 2 重新启用，后台识别分类和备注后只更新本地记录，不再向飞书写入
- **状态卡片简化**：去掉独立的「飞书」状态格，简化为「GLM / 模式」两格

---

## v0.18.0 — 飞书链接解析容错与反馈
**日期**：2026-03

### 变更内容
- 修复粘贴带 `?from=from_copylink` 参数的飞书链接无法识别的问题：App Token 和 Table ID 现在分开处理，有 Token 就存，缺 Table ID 时给出明确提示
- 链接解析结果实时显示：解析成功显示绿色「解析成功 ✓」，失败显示红色具体原因（格式错误 / 缺少 Table ID 等），不再静默失败

---

## v0.17.0 — 移除一键建表功能
**日期**：2026-03

### 变更内容
- 移除「一键创建记账表格」按钮及相关逻辑，简化飞书配置区块
- 移除飞书 Section footer 中关于 drive:drive 权限的提示文案
- 清理 `FeishuBitableService` 中的建表相关代码（`createExpenseTable`、`createBitable`、`getDefaultTableID`、`createExpenseFields`）

---

## v0.16.0 — Phase 2 超时修复：图片不再重复编码
**日期**：2026-03

### 变更内容
- 修复 Phase 2 偶发 timeout 问题：原先 Phase 1 和 Phase 2 各自对图片进行一次压缩编码，Phase 2 在后台 Task 中重新编码耗时叠加，导致网络请求超时
- 改为在 Phase 1 前统一编码一次，Phase 2 直接复用 Base64 字符串，节省 1-2 秒

---

## v0.15.0 — AppShortcut 自动注册，快捷指令无需手动创建
**日期**：2026-03

### 变更内容
- `screenshot` 参数改为可选（`IntentFile?`），App 安装后「立即记账」快捷指令自动出现在系统中，无需手动在快捷指令 App 新建
- 未传入截图时返回明确引导提示，说明需在快捷指令中连接「截屏」动作

---

## v0.14.0 — 零门槛本地模式 & 飞书一键建表
**日期**：2026-03

### 变更内容
- **飞书变可选**：只需填入 GLM API Key 即可开始记账，飞书未配置时自动切换为「本地模式」，记录保存在本地；dialog 提示「✅已记账（仅本地）」，不再显示红色错误状态
- **状态卡片升级**：第三格由「就绪/未就绪」改为「云同步 / 本地 / 未就绪」三态，GLM 配置后即为绿色，降低配置压力
- **飞书区块折叠**：飞书配置区默认折叠为「飞书 Bitable（可选，云端同步）」，未配置时呈灰色，不干扰主流程
- **飞书一键建表**：填入 App ID 和 App Secret 后，点击「一键创建记账表格」即可自动创建「Plutus 记账」多维表格、建立所有字段，并将 App Token 和 Table ID 自动回填设置页
- **GLM 注册引导**：API Key 输入框下方新增「去获取 API Key →」直达链接，跳转智谱 GLM 控制台

---

## v0.13.0 — 两阶段分类体系 & 商户识别优化
**日期**：2026-03

### 变更内容
- **消费分类重构**：将原来 6 个一级分类扩展为两级体系，AI 只识别二级分类（32类），一级分类（9类）由本地规则推导，无需额外 API 调用
- **两阶段识别架构**：Phase 1 只识别金额/商户/时间（prompt 精简，速度快），识别完即写入飞书并弹出 dialog；Phase 2 后台静默识别分类和备注，完成后 PATCH 更新飞书记录，用户无感知等待
- **商户识别优化**：新增规则——品牌简称优先于工商注册全称，过滤含「市」「区」「有限公司」等字样的长文本（解决喜茶被识别为「广州市海珠区超鹏饮品店」的问题）
- **去除支付渠道字段**：从模型、本地存储、飞书写入全面移除，简化数据结构
- **图片处理性能优化**：压缩操作移入 `Task.detached` 后台线程，不阻塞主协程

### 技术实现
- `GLMVisionService` 拆分为 `analyzeCore()` 和 `analyzeDetail()` 两个方法，`max_tokens` 降至 256
- `FeishuBitableService.addRecord()` 改为返回 `record_id`，新增 `updateRecord()` 用 PUT 补全分类字段
- `ExpenseRecord` 引入 `CoreExtraction` / `DetailExtraction` 两个解码模型，新增 `withDetail()` 和 `ExpenseRecordStore.update(id:with:)`

---

## v0.1.0 — 初始版本
**日期**：2026-03

### 核心功能
- Action Button → Shortcuts → App Intent 完整链路
- 调用 Claude Vision API 识别截图中的消费信息
- 识别字段：金额、货币、消费类型、商户、交易时间、备注
- 写入飞书 Bitable 多维表格（tenant_access_token 自动刷新）
- 发送 iOS 本地通知告知识别结果
- SwiftUI 设置页：API Key 配置、飞书配置、Action Button 引导
- 本地缓存最近 20 条消费记录

---

## v0.2.0 — 切换至 GLM Vision
**日期**：2026-03

### 变更内容
- 将 AI 模型从 Claude Vision 替换为智谱 GLM（`glm-4v-flash`）
- 接入端点：`https://open.bigmodel.cn/api/paas/v4/chat/completions`
- 图片压缩至最大 1024px / 1MB，转 Base64 传输

---

## v0.3.0 — 全屏适配 & 项目结构清理
**日期**：2026-03

### 变更内容
- 修复 iPhone 17 Pro Max 界面未全屏问题（缺少 `UILaunchScreen` 键）
- 将所有自定义 Info.plist 属性迁移至 `project.yml` 的 `info.properties`，防止 `xcodegen generate` 覆盖
- 拍平项目目录结构，移除多余的嵌套 `ExpenseCapture/` 层级

---

## v0.4.0 — 品牌改名 & UI 重构
**日期**：2026-03

### 变更内容
- 应用名由 ExpenseCapture 改为 **Plutus**
- 新增底部 Tab Bar，两个 Tab：「配置」「日志」
- 将运行日志（IntentLogger）独立到「日志」Tab，支持单条复制和全部复制
- 去除截图来源字段
- 应用图标换用极简黑金风格

---

## v0.5.0 — 识别准确率优化（多轮）
**日期**：2026-03

### Prompt 优化
- 新增消费类型品牌映射规则（古茗→餐饮、瑞幸→餐饮、滴滴→交通等）
- 新增支付渠道识别规则（财付通→微信、页面主题色判断等）
- 修复负数金额问题：`-¥6.90` 中 `-` 仅表示支出方向，amount 取正值
- 交易时间格式统一为 `yyyy-MM-dd HH:mm`，精确到分钟
- 支付渠道限定为固定枚举，防止将 T3出行等商户名误填为渠道

### 商户识别优化
- 建立商户识别优先级规则：
  1. 圆形 logo 旁紧邻的短文本（最可靠）
  2. 金额正上方或正下方的短文本
  3. 页面明确标注的商户字段
  4. 订单标题、收款备注
- 新增规则：品牌简称优先于工商注册公司全称（过滤含「市」「区」「有限公司」等字样的长文本）

---

## v0.6.0 — 飞书字段修复
**日期**：2026-03

### 变更内容
- 修复飞书写入报错 `FieldNameNotFound`：新增字段名映射配置，用户可在 App 内自定义字段名与飞书表格列名保持一致
- 修复飞书 DateTime 字段报错 `DatetimeFieldConvFail`：日期字段改为毫秒时间戳，支持 11 种日期格式解析，解析失败兜底当前时间
- 删除货币字段（默认人民币）

---

## v0.7.0 — 通知与流程优化
**日期**：2026-03

### 变更内容
- 去除 iOS 本地通知，改为通过快捷指令 dialog 展示识别结果
- 成功 dialog 文案：`✅已记账 ¥6.90 古茗`
- 非核心字段（消费类型、交易时间）缺失时降级为 warning，不阻断写入流程，只要金额和商户都存在即可写入

---

## v0.8.0 — 三 Tab 布局 & 图标升级
**日期**：2026-03

### 变更内容
- 底部 Tab Bar 新增「记录」Tab，展示最近 100 条消费记录
- 「配置」Tab 移除历史记录模块
- 本地记录存储上限从 20 条提升至 100 条
- 三个 Tab 标题下方增加 8px 间距
- 应用图标换用 Palatino 衬线字体，纯白背景黑色「Plutus」文字

---

## v0.9.0 — 识别性能优化
**日期**：2026-03

### 变更内容
- 图片压缩处理移入 `Task.detached(priority: .userInitiated)` 后台线程，避免阻塞协程
- 尝试将图片分辨率上限降至 512px 以加快上传（因识别准确率下降已回滚，保持 1024px）

---

## v0.10.0 — 消费分类体系重构
**日期**：2026-03

### 变更内容
- 消费分类由原来 6 个一级分类重构为两级体系：
  - **一级分类**（9类，本地推导，无需 AI）：餐饮、居家生活、人情费用、行车交通、购物消费、医疗、公益、休闲娱乐、保险
  - **二级分类**（32类，AI 识别）：外出就餐、外卖、水果、零食、买菜、奶茶、饮料酒水、物业费、水电燃气、电器、手机话费、红包、礼物、地铁公交、长途交通、打车、生活用品、电子数码、美妆护肤、衣裤鞋帽、书报杂志、珠宝首饰、宠物、美发、医疗、药物、慈善、娱乐、旅游、按摩、运动、保险
- 飞书表格同步写入「一级分类」和「二级分类」两个字段
- 记录列表展示格式更新为「一级分类 · 二级分类 · 时间」

---

## v0.11.0 — 两阶段识别架构
**日期**：2026-03

### 背景
GLM Vision API 调用耗时较长，用户需等待识别+写入飞书全部完成才能看到结果。

### 变更内容
将识别流程拆分为两个阶段：

**Phase 1（用户等待，~2-3s）**
- 精简 prompt，只识别金额、商户、交易时间
- 识别完成后立即写入飞书（仅含核心字段）
- 弹出快捷指令 dialog 告知用户

**Phase 2（后台静默，用户无感知）**
- 基于 Phase 1 已知的商户名，识别二级分类和备注
- PATCH 更新飞书已有记录，补全分类字段
- 更新本地缓存记录

### 技术实现
- `GLMVisionService` 拆分为 `analyzeCore()` 和 `analyzeDetail()` 两个方法
- `FeishuBitableService.addRecord()` 改为返回 `record_id`，新增 `updateRecord()` 用 PUT 补全字段
- `ExpenseRecord` 新增 `withDetail()` 方法，`ExpenseRecordStore` 新增 `update(id:with:)` 方法
- `max_tokens` 从 1024 降至 256，进一步压缩响应时间

---

## v0.12.0 — 记录页跳转飞书
**日期**：2026-03

### 变更内容
- 「记录」Tab 右上角新增「查看全部」按钮
- 点击直接在浏览器打开对应飞书多维表格（`https://feishu.cn/base/{appToken}?table={tableID}`）
- 仅在飞书 App Token 已配置时显示该按钮
