# Code Coach 0.4.0 validation - 2026-11-14

- Current and resolved histories now have separate count/filter buttons; the overview practice-count column was removed. Learning topics are on the Practice page.
- Topic selection sends only that topic's statistics to the quiz client. Each generated quiz keeps its locally captured source diagnostic, file and line. New diagnostics capture at most 1000 characters from the actual reported source line; old payloads with no sourceLine decode without fabricating a snippet.
- 25 core tests passed, zero skipped: previous 21 plus resolution/recurrence filter partitioning, topic-specific context/references, legacy JSON decoding and snippet privacy, and real javac CRLF line alignment. See LEARNING_TEST_RESULTS.txt.
- Full app compilation and ad-hoc signature integrity passed. No changes to Xcode source membership were needed because helpers were added to existing files. Full Xcode is unavailable.
- Current installed app was updated with prior-version backup; learning database and stored Token were preserved. Normal diagnostic reconciliation may add/update the new snippet field on the next successful check.
- Native UI inspection was attempted twice but the computer-use service timed out. Therefore full clicking/visual acceptance of the new screen is NOT claimed. No live Databricks quiz was generated during validation, so semantic teaching quality and live response/reference presentation still require user validation.
- Startup was additionally changed to a noninteractive Keychain existence/status query, rather than decrypting the Token on the main thread. Real credential access/locked-keychain behavior was not tested with user credentials.
- The app remains ad-hoc signed. Updating can invalidate accessibility grants. Launch from /Applications/CodeCoach.app after closing previous copies; do not infer editor support from a granted permission alone.

## Earlier validation

# Code Coach 0.3.1 Token paste validation

- Added the standard Edit menu and panel routing for Command-V, Command-A and other standard text editing actions. Added a manual clipboard-paste button; it does not save automatically.
- 12 native window/shortcut assertions passed, including one-time paste dispatch to the active responder and ignoring unrelated modifier combinations. Full app compilation and local signature integrity passed.
- Installed at /Applications/CodeCoach.app with previous app backup. Actual native UI test pasted a dummy value into the empty secure Token field; the masked value appeared and Save Token became enabled. Command-A / Backspace cleared it and Save became disabled again.
- No test Token was saved. No Databricks request was sent. No real Token or clipboard contents were exposed to the assistant. The UI automation paste helper temporarily used the clipboard and restored its previous contents.
- The explicit clipboard button is present in the inspected UI; it was not clicked with the user's unknown clipboard contents. The shortcut route was tested with dummy text.
- The updated app currently shows accessibility authorization unavailable. The update changed the ad-hoc code identity, so local monitoring may need user reauthorization; clipboard editing does not depend on that permission. No system permissions were changed by this fix.

## Previous validation

# Code Coach 0.3.0 Databricks validation - 2026-11-14

This section supersedes older AI integration descriptions below. Local detection and window interactions are unchanged.

- Configured the exact HTTPS Unity Gateway endpoint and system.ai.gpt-oss-120b model supplied by the user. No token was supplied, requested in chat, or used for a real API call.
- Added manual quiz generation, selected-error explanation with request preview, and an optional billable connection probe. A Databricks-specific Keychain service isolates credentials from the prior OpenAI key.
- Added ephemeral URLSession networking that refuses redirects, handles string/text-block completions, excludes reasoning blocks, validates schema results, rejects incomplete replies, and sanitizes HTTP error bodies.
- 21 core test methods passed: the previous 15 plus 6 Databricks mock tests for configured URL/model/header/payload, GPT-OSS blocks, explanation data minimization, HTTP failures, invalid/truncated content, and a connection probe/header injection guard. See DATABRICKS_TEST_RESULTS.txt.
- These are mock tests, not validation of the real workspace permissions, token lifecycle, model availability, billing, or model quality. Real Token/Keychain and AI requests remain to be tested by the user in the app.
- Full Xcode is unavailable. Sources compile with the command-line Swift/macOS SDK, project structure and source references are checked, and the final app uses local ad-hoc signing. An update can invalidate prior accessibility authorization; this integration does not change the local detection algorithm.

## Prior validation history

# Code Coach 0.2.1 window interaction validation - 2026-11-14

This section supersedes the 0.2 interaction observations below.

- Full release app compiled and installed in /Applications/CodeCoach.app. The previous 0.2 app was backed up; learning records and API Key were not changed.
- 15 core test methods passed, zero skipped and zero assertion failures (LIVE_TEST_RESULTS.txt). New coverage distinguishes clicks from drags, including dragging out and back to the start, mouse-up displacement, and gesture reset.
- Native titlebar: 8 assertions passed (WINDOW_TEST_RESULTS.txt), covering first-click acceptance, coordinate-aware close-button isolation, the full title drag surface, ten consecutive close actions and replacing callbacks. These are in-process tests without onscreen input injection.
- Actual native UI: three open/close cycles succeeded; a header drag was followed by a successful close; dragging the compact widget left it compact, and it remained clickable afterwards.
- Screenshots are cropped to the window, so absolute drag distance and every screen boundary were not quantified. Multiple displays and every inactive-window combination were not exhaustively tested.
- AX queries now run off the main actor, with per-element timeouts and session validation after asynchronous reads. No real editor slowdown was injected during UI verification.
- The updated app showed accessibility permission unavailable. It was left compact and paused. Real monitoring while dragging/closing still requires the user to reauthorize the updated ad-hoc-signed application and test an editor. Existing editor compatibility and single-file limitations remain.

## Archived 0.2 validation

# Code Coach 0.2 验证记录 · 2026-11-14

本记录取代 0.1 的验证状态。

## 已验证

- arm64 Mac，Apple Swift 6.3.3，Command Line Tools macOS SDK：完整原生源码编译成功，最低目标 macOS 13。
- 新版 Xcode 工程已加入 EditorReader / LiveSource 源码；结构、共享 scheme XML 和源码引用检查通过。没有完整 Xcode，不能声称运行了 xcodebuild。
- 新版将关闭控件改为 xmark，删除所有项目文件夹选择/轮询入口，使用辅助功能读取器；代码中没有截图、OCR、全局按键监听或 IDE 插件。
- 14 项核心测试通过（实际日志见 LIVE_TEST_RESULTS.txt），包含新增加的未保存文本检查、真实 javac 类型错误、文件名选择/拒绝非 Java 内容、路径穿越校验与临时源码清理。旧版分析器、SQLite、匿名出题 payload、网络 mock 的回归测试仍运行。
- Apple Silicon 预编译应用内置官方 Temurin JDK 21.0.13+9；使用捆绑 javac 再次运行核心测试。应用 ad-hoc 签名完整性检查通过。

## 没有验证，不能宣称已实现兼容

- 用户尚未为此版本授予辅助功能权限；没有实测从 VS Code、IntelliJ、其他编辑器获取未保存代码。读取白名单不代表兼容性认证。
- 不同 IDE 的 AX 层级、文本截断、窗口/文档身份、权限撤销，以及其无障碍设置对代码读取的影响尚待真实验收。
- 新版已直接替换 /Applications/CodeCoach.app，备份旧版且保留偏好设置/钥匙串。已启动并通过原生界面观察确认：首页没有文件夹入口，有可见 X 关闭按钮、辅助功能授权说明、初始暂停状态。因界面在测试中发生用户操作变化，未完成 X 点击收起和拖动的最终验收；不能以 0.1 的观察代替。
- 单文件 javac 没有项目依赖上下文。跨文件引用、外部库等可能产生误报；不能称为 IDE 级完整诊断。
- 未使用真实 API Key 请求 OpenAI；未验证真实钥匙串保存/授权/删除。网络测试为 mock。
- 未验证 Intel、旧 macOS、多显示器/全屏、VoiceOver、Developer ID 公证或 Gatekeeper 下载行为。

应用不能静默授予辅助功能权限。交付后必须由用户在系统设置中亲自允许，再以真实编辑器测试是否能读取完整 Java 文件。若读取失败，应保持“未连接/不可读取”提示，不能替换成假成功或假诊断。
