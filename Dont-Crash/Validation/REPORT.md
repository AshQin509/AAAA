# Validation report — Code Coach 0.5 English revision

Validated on the user's Mac environment on November 14, 2026 (America/Chicago): Apple Silicon, Xcode 27.2, Apple Swift 6.4.2. Work began from `/Users/amber/Downloads/AAAA-main.zip`, the locally available original archive; `/mnt/data/AAAA-main.zip` was not present in this desktop environment. The Downloads project and existing app were not overwritten.

## Completed checks

- Shared `CodeCoach.xcodeproj` / CodeCoach scheme: **BUILD SUCCEEDED**, final source, Debug, both arm64 and x86_64 compilation. Code signing disabled for this verification. This does not constitute runtime testing on an Intel Mac.
- Native command-line `scripts/build-app.sh`: **succeeded**, producing an ad-hoc signed Apple Silicon app. The later final Xcode build also verified the bounded-read source correction.
- `scripts/test.sh`: **28 XCTest tests, 0 failures, no skips**. Includes actual installed `javac` integration, valid and broken Java, dependency isolation, cancellation, source cleanup, Unicode paths, diagnostic recurrence, local persistence, learning statistics, quiz validation, provider request schemas, response validation, and sanitized failures.
- New migration regression: existing Chinese category/attempt labels migrate together to English, preserving answer and diagnostic counts.
- OpenAI tests use intercepted URLSession requests, no real credentials or network inference. They verify the Responses endpoint, `store:false`, English instructions, explanation payload boundaries, connection probe, malformed header rejection, refusals, incomplete responses, and HTTP failures. Databricks mock coverage remains intact.
- `scripts/test-source-file.sh`: **passed** for reading without Accessibility, saved edits, stable identity, deleted files, and the 2 MB limit. This caught a cached file-size bug, fixed with a bounded file read and post-read size validation.
- `scripts/test-window.sh`: **12 assertions, 0 failures**, native interaction helpers; no onscreen window or input injection.
- Source/README scan: no Chinese text remains in application source string literals or README. Chinese escapes remain intentionally in the backward-compatible database migration; Unicode test filenames are also intentionally retained.
- Original archive script permissions were corrected so documented `./scripts/...` commands can execute.

Logs provided alongside this report: `TEST_RESULTS.txt`, `SOURCE_FILE_TEST_RESULTS.txt`, `WINDOW_TEST_RESULTS.txt`, and `XCODE_BUILD_RESULTS.txt`.

## Not established by these checks

- A visual UI inspection could not be completed: the computer-use app inspection timed out. English labels compile, but every screen has not been visually reviewed.
- No live OpenAI or Databricks request was made. No real key was requested, read, stored, or sent during validation. Your credentials, billing, workspace availability, and model permissions still need the manual connection test.
- No cross-IDE Accessibility test matrix was completed. The allowlist is not a compatibility guarantee. Use the tested saved-file path for the demo if the exact IDE does not expose full source text.
- No claim of whole-project Maven/Gradle checking, automatic dependency resolution, all-editor support, logic correctness, local model hosting, free API access, notarization, or Intel runtime validation is made.

## Main implementation changes

- English UI, native menus, messages, topic categories, model instructions, README, and build launcher; English development region.
- OpenAI selectable alongside preserved Databricks. Separate Keychain services, provider-specific saved model IDs, session-only consent, provider/model changes cancel pending tasks, provider captured with each request. OpenAI and legacy quiz entry points use the same hardened production request implementation.
- Saved `.java` file selection and polling, independent of Accessibility and editor choice; bounded UTF-8 reads with explicit unavailable errors.
- Automatic JDK discovery via `java_home`, user/system JDK folders, Homebrew, SDKMAN, and optional bundled JDK. Refresh and Start rediscover installations; advanced executable selection remains optional.
- Panel opens expanded at launch to make the app easier to find, while checking remains paused.
- Learning history migration preserves old topic/answer associations.
