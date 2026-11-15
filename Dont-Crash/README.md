# Don't Crash — native macOS demo checkpoint

Open `CodeCoach.xcodeproj`, select the **CodeCoach** scheme and **My Mac**, then press **Command-R**. The visible app is named **Don't Crash**. Internal project/module/storage identifiers remain unchanged to retain compatibility and saved learning history.

The panel opens expanded. Use Coach, Habits, Practice, Progress, and Settings in the top navigation. The titlebar is draggable; Close or Escape collapses to the floating icon. Start/Pause controls editor/file monitoring. Monitoring is off at launch. Reasoning requests require separate explicit consent and a manual click.

## Try the reasoning workflow

Coach contains a maximum-finding example whose initialization can fail for all-negative input. Review or replace the text, choose its language, enable manual AI requests, and select **Analyze my reasoning**. DeepSeek receives that text. Review saved feedback in Habits, then request the day's three questions in Practice. Select an answer, then press **Check my answer**. Progress shows saved counts, not mastery claims.

The DeepSeek key must already be stored locally in Keychain under service `com.stucksense.deepseek`, account `api-key`. The earlier developer helper is provided in the sibling `StuckSense-Developer` output folder. Do not paste a key into chat or source. No live DeepSeek result has yet been verified.

## Existing tools

Coach's **Java compiler diagnostics** disclosure retains the earlier compiler and error history. Practice's **Earlier diagnostic-based practice** disclosure retains the previous quiz workflow. Settings retains existing controls. Accessibility support varies by editor; saved-file mode is the fallback. Explicit reasoning text can use Java, Python, JavaScript, C, C++, or R without requiring those runtimes.

## Build and test

```sh
./scripts/build-app.sh
./scripts/test.sh
./scripts/test-source-file.sh
./scripts/test-window.sh
```

The command-line build still writes `build/CodeCoach.app`; its display name is Don't Crash. The source requires macOS 13+ and compatible Xcode/Swift tools. A JDK is needed only for Java compiler checks.

Read **UX-CHANGES.md** for every adaptation, changed source file, and carried-forward limitation. This is a testable development checkpoint, not a claim that all previously requested features are complete.
