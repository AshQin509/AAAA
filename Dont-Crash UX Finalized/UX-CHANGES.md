# Don't Crash — UI adaptation report

## Reference reviewed

Reviewed `CodeCoach 2.zip`, particularly `extension/media/coach.js` and `coach.css`. The archive includes a VS Code extension, a server, and Swift sources. Used only the extension's design patterns as inspiration; did not import its backend, monitoring code, dependencies, or VS Code architecture.

Worth adopting: direct navigation, connection context near the main action, prominent action buttons, separate evidence cards, deliberate answer submission, and progress framed as evidence rather than ability labels. Its small CSS text sizes were not copied: this version uses larger native text.

## Every source change from our previous checkpoint

- `Sources/CodeCoach/Views.swift`: five direct destinations (Coach, Habits, Practice, Progress, Settings); source-selection shortcuts in Coach; existing compiler diagnostics in an expandable section; earlier diagnostic practice retained in an expandable section; topic-practice navigation updated to the correct destination; supporting text raised to 13–14 points and code to 14 points; panel enlarged from 440×650 to 620×720; privacy wording corrected to distinguish local monitoring from explicitly shared reasoning text.
- `Sources/CodeCoach/ReasoningView.swift`: removed the nested navigation selector; section chosen by top-level navigation; clearer Coach heading and source-sharing instructions; prominent Analyze my reasoning button; observation cards with more spacing; practice choice selection separated from submission; new Progress summary displays actual saved observation, confirmation, dismissal, and current practice completion counts. It explicitly says the starter example is not segregated into demo history yet. No mastery or trend claims added.
- `Sources/CodeCoach/WindowChrome.swift`: visible title Don't Crash, language-neutral subtitle, 20-point title, 12-point subtitle, adjusted title layout; retained native dragging and close controls.
- `Sources/CodeCoach/Main.swift`: renamed menu and accessibility labels, matched expanded window size to the new panel.
- `Sources/CodeCoach/AppModel.swift`: renamed the app in Accessibility permission instructions. No monitoring/analysis behavior changed.
- `Info.plist`: display name and bundle name changed to Don't Crash.
- `README.md`: replaced old release instructions with this checkpoint's build/run guidance.

No networking, compiler, file-reader, persistence, or Keychain implementation changed in this UI pass. Existing executable, module, scheme, bundle identifier, storage folder, and Keychain service identifiers remain for compatibility. Xcode's scheme is still CodeCoach. Earlier delivery folders are preserved.

## Features retained

Floating companion, titlebar dragging, close/Escape collapse, start/pause, approved editor Accessibility reads, saved Java file monitoring, Java discovery, compiler/history tools, old provider tools pending DeepSeek verification, manual multilingual DeepSeek reasoning, confirmation/dismissal, daily three-question practice, saved answers, consent and cancellation.

## Existing limitations carried forward

DeepSeek live inference has not been verified. Earlier probe found no key in `com.stucksense.deepseek` / `api-key`. The UI changes do not resolve that. Compiler monitoring remains Java-only; explicit reasoning text supports the language selector. Daily practice remains multiple choice, with no code execution or independent runtime verification. Recurring-habit aggregation, practice-history-informed generation, dedicated hints, and separated demo history remain unfinished. The legacy OpenAI/Databricks tools remain pending successful DeepSeek migration. No live cross-IDE compatibility matrix or visual UI inspection was completed in this pass.

## Source capture follow-up

Fixed the missing bridge between editor/file monitoring and manual reasoning. Coach now offers Preview captured code, copying an explicitly captured snapshot into the review box without sending it. Pause clears the pending capture; pasted/reviewed text remains available for an explicit manual request. Unavailable editor reads clear the pending capture. File recognition includes Java, Python, JavaScript, C/C++, and R; Accessibility uses matching source filenames when available. Monitoring no longer requires a JDK. Non-Java source is captured without claiming a compiler check. Java compilation remains supporting evidence. Files over the 30 KB AI limit require selecting/pasting a smaller example.

Latest conceptual feedback is now visible in Coach. New daily practice requests include previous questions and answers as well as observations. These include potentially sensitive conceptual evidence; manual consent is still required.

Build passed. Live connection from the separate local probe remains unverified: it reported the expected Keychain item missing. This does not establish whether a separately launched GUI app can access a key. No live classification success is claimed. Earlier unfinished functions and old-provider cleanup remain outstanding.

## Learning profile update

ReasoningView.swift now stores optional source-event hashes and example labels on observations, preserving older records. Habits groups matching normalized concept labels across languages, counts distinct source events, and distinguishes a single observation from a possible recurring pattern. This is exact normalized-label grouping, not semantic clustering of synonyms. Explicit example history is idempotently loaded and excluded from personal practice and Progress observation counts. Older unmarked history is not retroactively classified.

Completed daily practice sets are archived when a new daily set replaces them; the prior seven sessions are included in generation context. Progress lists archived dates and completion counts. Practice has local counterexample/trace hints, larger controls, and an explicit Stop AI request action. Default reasoning-view text is 16 points. No runtime execution or independently verified code-writing assessment is claimed.

Verified: Xcode build; isolated profile test covering example labeling, repeat-load prevention, personal separation, source deduplication and persistence. No live network request was made in this update. Still outstanding: semantic concept taxonomy, independently constructed code answers with tests, per-concept longitudinal scores, full provider cleanup and comprehensive visual/live-editor validation.

## Demo scope freeze

Prioritized clear capture-to-analysis flow, consistent DeepSeek controls, cancellation correctness, daily practice, and local data management. Coach now starts empty with explicit instructions rather than preloaded sample code. Settings exposes the same reasoning consent and DeepSeek probe; earlier provider settings remain collapsed and clearly labeled to preserve prior features. Cancelled tasks cannot overwrite the busy/error state of newer tasks. Clear-all now also clears reasoning observations and practice archives after the existing confirmation.

Deferred beyond this demo: executable code grading, semantic matching of differently named concepts, sophisticated longitudinal scoring, automated runtime analysis, and backend/account infrastructure. Existing features are preserved; this scope decision does not remove saved data. Visual polish is the next priority. Build passed; isolated history regression passed. Live network inference and visual inspection were not performed during this cleanup.

## Credential and input repair

Added developer-only startup flag `--configure-deepseek` to the native app. It presents a secure field, saves to `com.stucksense.deepseek` / `api-key`, and verifies read-back in that same app process. It sends no API request. `scripts/configure-deepseek.sh` builds and opens this mode. This replaces the separate-helper setup path for the demo without exposing key settings to ordinary launches. The existing user's key has not been inspected or copied.

Selecting a source file now performs a bounded background read and fills the reasoning preview immediately while monitoring is active. Cancellation, selection changes, or pause discard pending reads. Network sending still requires explicit consent and Analyze. The native build passed. A real key setup and live request still require local user interaction; neither is claimed as verified.
