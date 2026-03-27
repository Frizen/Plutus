# Plutus 项目规则

## 自动更新 CHANGELOG

**每次完成功能变更后（无论大小），必须在结束前自动更新 `CHANGELOG.md`**，无需用户提醒。

### 规则细节

1. **触发条件**：任何对以下文件的修改完成后：
   - `ExpenseCapture/**/*.swift`（代码逻辑变更）
   - `ExpenseCapture/Assets.xcassets/**`（资源变更）
   - `project.yml`（项目配置变更）

2. **更新时机**：在 commit 之前更新 CHANGELOG，使其包含在同一个 commit 中。

3. **版本号规则**：在现有最新版本号基础上递增 patch 版本（如 v0.12.0 → v0.13.0）。

4. **记录格式**：
   ```markdown
   ## vX.Y.Z — 简短标题
   **日期**：YYYY-MM

   ### 变更内容
   - 具体改动描述（面向产品，不要堆砌技术细节）
   ```

5. **写作风格**：
   - 面向产品功能描述，避免纯技术术语堆砌
   - 重要的技术实现可以单独列「技术实现」小节
   - 每条变更用一句话说清楚「做了什么」和「解决了什么问题」

## 其他项目约定

- 新增 Swift 源文件后需运行 `xcodegen generate` 重新生成 `.xcodeproj`
- commit message 使用中英文均可，遵循 conventional commits 格式
- 不要 commit Xcode 用户数据文件（`xcuserdata/`、`UserInterfaceState.xcuserstate`）
