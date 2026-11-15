# Code Coach 0.4.0 · 当前编辑区实时检查

## 0.4 问题筛选和分类练习

- 概览仅保留“当前问题”和“历史问题”两张可点击筛选卡；当前列表只含 active 的未解决问题，历史列表只含 inactive 的已解决记录，数量与筛选范围一致。删除练习次数栏目。
- 学习线索移到练习页。选择一个知识点分类后，出题请求只包含该分类的匿名统计；其他分类、文件名、行号、诊断原文和代码行不附加到出题请求。
- 可以从问题卡片点击“按此知识点练习”，也可以在练习页选知识点、选择对应错误行。生成时固定关联文件/行号快照，避免之后切换分类或修改代码时，把旧题错误标到新位置。
- 每条新检测到的错误在本机 SQLite 中保存对应的一行源码快照（最多1000字符），用于已解决记录和练习位置显示。不是保存完整源码；这些片段可能含敏感数据，删除学习记录也会删除这些片段。
- 旧记录没有代码片段时明确说明，只展示保存的文件和行号，不从当前文件猜测历史内容。行号仍取决于编辑器提供的文本范围，不支持截断缓冲区的可靠定位。
- 当前/历史/学习线索均按当前识别的 Java 文档隔离，显示最近500条记录。离开编辑区时保留上一份检查结果并显示连接状态。历史“已解决”表示最近成功检查不再返回该条诊断；移动行号或改报错内容也可能创建新条目，这仍是现有去重规则的限制。
- 启动仅进行不弹窗的钥匙串凭证状态查询；Token 明文仅在手动 AI 请求时由应用读取。如果钥匙串锁定或状态不可用，显示明确提示。



0.3.1: Token input supports Command-V via a standard Edit menu and panel responder routing, plus an explicit Paste Token button. A dummy value was pasted in the installed secure field, the Save button became enabled, and the value was cleared without saving or sending a request.


本次修复拖动和关闭：顶部整条标题栏（除关闭按钮）均可拖动，关闭按钮使用独立原生控件；小圆标在松开鼠标后区分点击和拖动。编辑器读取已移到后台，避免阻塞窗口操作。新增原生控件测试可通过 `./scripts/test-window.sh` 运行，结果见 `Validation/WINDOW_TEST_RESULTS.txt`。

这是从“选择文件夹、检查保存文件”改成的新版。**不再需要导入 Java 文件、选择项目文件夹或固定选择 IDE。** 桌面默认只有小圆标，点击展开，「×」或 Escape 关闭面板后保留小圆标。

## 开始使用

1. 打开 CodeCoach.app，点击小圆标。
2. 首次点击“允许实时读取”，在 macOS「系统设置 → 隐私与安全性 → 辅助功能」中亲自允许 Code Coach。应用不会代你授权，也不申请屏幕录制权限。
3. 回到 Code Coach 点击“开始”，切换到代码编辑器，点击 `.java` 代码区域。
4. 编辑器通过辅助功能提供代码文本时，停下输入后会在本机进行单文件 Java 检查，**未保存的修改也参与检查**。没有读取到代码时会明确显示等待/不支持，不会假装检查通过。
5. 点击圆标看检查提示；「×」关闭面板，监测继续；点击“暂停”停止读取。每次启动均为暂停，不自动联网。

本次 Apple Silicon 预编译版本内置官方 Eclipse Temurin JDK 21.0.13+9，不再要求你手动找 javac 路径。源码自行构建默认使用系统 JDK，也可指定内置 JDK（见下文）。

菜单栏 `{}` 可找回窗口或退出应用。本地 ad-hoc 签名，未进行 Developer ID 公证。

## 参考 Grammarly 的方式与边界

Grammarly 官方说明其 Mac 客户端依赖辅助功能权限，在受支持的应用中提供文字建议；悬浮标志可拖动，点击后查看建议，X 关闭回到悬浮状态。本版参考其“授权 → 当前编辑区 → 安静检查 → 点击查看”的交互。

官方来源：[辅助功能权限](https://support.grammarly.com/hc/en-us/articles/360059770451-Why-does-Grammarly-need-access-to-accessibility-features)、[用户指南](https://support.grammarly.com/hc/en-us/articles/4412816078349-Grammarly-for-Windows-and-Grammarly-for-Mac-user-guide)。这些公开资料不能证明其未公开的内部实现，也不能证明任意 IDE 都兼容。

**本版本是通用读取方案的实验实现，并未完成跨 IDE 实测。** 本机尚未授予新版本辅助功能权限，故不能宣称已经能在 VS Code / IntelliJ / 任意应用中稳定读取未保存代码。

- 当前尝试自动连接的编辑器类别包括 VS Code / Insiders / VSCodium、Cursor、Zed、Sublime Text、JetBrains 系列、Eclipse、NetBeans 和 TextEdit。该列表是安全读取白名单，**不是已经验证通过的兼容性列表**。
- 仅尝试读取有 Java 文件标题/文档属性，或未命名文件的代码文本区域；不读取浏览器、聊天应用、终端、密码管理器或任意其他应用。未命名内容还需包含 Java 类型声明。
- 编辑器必须暴露可访问的 `AXTextArea` 和文本值。部分编辑器需启用自身的无障碍/屏幕阅读器支持，有些只提供当前行或可见片段，有些完全不提供。遇到这些情况本版可能无法检查或产生片段相关错误；没有 OCR 或自动截图后备方案。不能保证“所有编辑器通用”。
- 读取当前编辑区不等于拥有项目上下文：本版把当前提供的代码放入临时文件，交给内置 javac 检查**单个文件**。不扫描项目、不解析 Maven/Gradle 配置，也不加载项目依赖。因此跨文件引用、外部库、Lombok、特定 Java 版本或模块等可能产生误报，必须在 IDE 中确认。检查提示不是完整项目的构建结果。
- 实时指停下输入后约 1–3 秒开始得到普通小文件结果，不保证逐字符即时。采样约 0.7 秒，连续两个相同内容后检查；编译耗时额外计算，约 20 秒超时。编译过程中内容改变时丢弃旧结果。
- javac 最多输出 100 个错误，当前代码上限 2 MB。只检查能得到的源码，不捕获运行时异常，不保证发现逻辑错误。
- 小圆标在普通应用窗口之上；不是直接嵌入编辑器内部，不绘制行内波浪线，也不会自动修改代码。多显示器、全屏 Space 和不同系统版本需实测。

## 隐私与控制

- **默认暂停**；只有手动授权并开始后才读取符合上述条件的当前编辑区。辅助功能权限由系统管理，随时可以撤销。暂停停止读取并取消编译。
- 不截图、不监听全局按键、不发送源码给 AI、不安装 IDE 插件、不自动下载依赖、不执行用户 Java 程序或注解处理器。
- 编译时会把当前源码放入本机随机临时目录，权限 0700，正常结束后删除。应用/系统意外退出可能残留临时副本；系统备份或快照也可能保留旧数据。不能声称源码永远不落盘。
- SQLite 保存在 `~/Library/Application Support/CodeCoach/learning.sqlite`，记录文件名、行号、检查消息、错误频次和答题统计，并为新诊断保存一行源码快照（最多1000字符），不存完整源码。消息有时包含标识符或片段。数据库没有单独加密，依赖本机账户和磁盘保护；本应用未启用 App Sandbox。
- 文档身份使用编辑器标识及文档地址/标题的哈希区分；无文档地址时窗口标题变化可能形成新的学习记录。去重键含文件名、行号、诊断代码及消息，因此移动代码行也可能形成新条目。
- “断开当前编辑区”暂停并清除当前显示，不删除历史数据库。“清除所有项目学习记录”会确认后删除所有旧/新版本学习记录，不删除 API Key。

## Databricks 出题与错误解释（可选）

0.3 使用用户提供的 Databricks Unity Gateway，不再由应用调用 OpenAI：

- Host: `dbc-b4f4fe67-acdc.cloud.databricks.com`
- Endpoint: `https://dbc-b4f4fe67-acdc.cloud.databricks.com/ai-gateway/mlflow/v1/chat/completions`
- Model: `system.ai.gpt-oss-120b`（设置中可改模型名，服务地址固定为此工作区）
- 请求使用 `messages`、`max_tokens:5000`、`response_format:json_schema`、非流式响应；兼容文本字符串及 GPT-OSS 的 text blocks，不解析 reasoning 文本作为答案。

使用方法：设置中输入自己的 Databricks Token → 保存 Token → 开启本次启动联网许可 → 测试连接。连接测试会发送固定测试指令、不含项目数据，也可能产生 API 费用。实际模型/结构化输出能力和权限需真实 Token 验证；本次未执行任何真实请求。

Token 单独保存在系统钥匙串，service 为 `com.codecoach.mac.databricks.<host>`；与旧 OpenAI Key 隔离，不迁移、不读取或发送旧 OpenAI Key。不要把 Token 粘到聊天或源码。只向上述固定 HTTPS 工作区地址发送请求，默认会话拒绝 HTTP 重定向；不会把 Token 跟随跳转发到其他地址。

两种 AI 请求的数据范围不同：

1. **出题**：只发送知识点、出现次数、答题次数和正确数，练习页可预览。不附加文件名、路径、原始诊断或源码。四选一并验证题目格式，提交后本地判分。
2. **解释错误**：在概览中展开某条记录的“AI 解释此错误”，预览后点击“发送这条诊断并解释”。只附加该条诊断的代码、消息、分类和单文件检查的上下文限制，不附加文件名、路径字段或源码全文。诊断文字本身可能含标识符、代码片段甚至路径，因此必须查看预览；不是匿名请求。AI 解释说明可能原因、修复步骤、自拟示例及不确定性，不能声称看过用户完整代码。

默认不联网，没有后台自动出题或解释。全局关闭联网、切换编辑文档、删除 Token 或取消请求时取消当前 AI 任务并丢弃过期返回；不能撤回已发送到工作区的内容。生成的解释仅在当前运行期间显示，不写入学习数据库。

工作区会接收 Token、IP、请求正文等信息。日志、保留、推理表及治理策略由该工作区和模型服务配置决定；本版不发送 OpenAI `store:false` 字段，不能用它推断 Databricks 不保留内容。AI 题目和解释可能有误。403/401、无模型、限流、拒绝、截断和错误格式均有处理。

原 OpenAI 客户端仍留在核心库供回归测试；0.3 的应用出题、连接测试及解释入口全部调用 DatabricksClient。

参考：[Databricks chat API](https://docs.databricks.com/aws/en/machine-learning/model-serving/query-chat-models)、[结构化输出](https://docs.databricks.com/aws/en/machine-learning/model-serving/structured-outputs)。

## 构建与测试

需要 macOS 13+、兼容 SDK 与 Swift 5.9+，无第三方 Swift 包依赖。

```sh
./scripts/build-app.sh
# 如果希望将官方 JDK Home 捆绑到应用（不自动下载）：
CODECOACH_BUNDLED_JDK="/path/to/JDK/Contents/Home" ./scripts/build-app.sh

CODECOACH_TEST_JAVAC="/path/to/JDK/Contents/Home/bin/javac" ./scripts/test.sh
```

输出 `build/CodeCoach.app`，按本机架构编译并 ad-hoc 签名。完整 Xcode 可打开 `CodeCoach.xcodeproj` 的共享 CodeCoach scheme。当前环境没有完整 Xcode，工程只做结构和引用检查；源码通过命令行编译。XCTest 通过 Swift Package 提供；Command Line Tools 环境使用同一份测试断言的独立运行器。缺少 JDK 时，相关集成测试会明确跳过。

核心保留了 0.1 的文件夹 javac 分析工具及相应测试，供回归验证；**新版应用不会调用项目文件夹扫描流程，也没有文件夹选择入口**。当前未保存文本检查使用 `LiveSource`。

## 验证状态

参见 `Validation/REPORT.md` 与 `LIVE_TEST_RESULTS.txt`。核心测试覆盖未保存文本、临时源码清理、文件名校验、真实 javac、SQLite 与模拟 API。辅助功能授权和真实编辑器读取必须在用户 Mac 上完成后验证；自动测试没有替代这一步。

## 第三方与许可证

应用源码为 MIT（LICENSE）。预编译版本捆绑的 Eclipse Temurin JDK 21.0.13+9 为独立第三方组件，保留原始 `Resources/JDK/legal/`、`NOTICE` 和 `release` 文件，遵循其各自许可证，包括 GPLv2 with Classpath Exception，不能把 JDK 视为本项目的 MIT 源码。官方二进制和对应源码获取入口：[Temurin 21.0.13+9 release](https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.13%2B9)。本次仅用于用户自己的 Mac 和私人交付，公开再分发前需保留并遵循所有第三方许可证条件。
