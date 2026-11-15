# Clearer interface and companion — November 15

## Changes
- White interface with blue controls, purple headings and teal practice suggestions. Body text stays dark for readability. Main text is 14–19 pt; title 20 pt.
- More spacing and divider lines between source connection, AI controls, code review and exercises. Code editor has a visible outline; Analyze appears before the previous result.
- Shortened introductions and privacy explanations. Normal coaching says AI and Test AI, rather than provider/setup terminology. Technical legacy tools remain collapsed; their functionality was preserved.
- New transparent companion artwork based on your supplied drawing. The floating canvas is 88×88 instead of 44×44 (four times the area). A brief opacity pulse signals detected compiler issues, respecting Reduce Motion. App, titlebar and menu-bar artwork use the same design.
- Show companion switches to the small draggable icon. Click the icon to open; right-click for Show, Start/Pause, and Quit. The menu-bar icon offers these actions too.
- Close hides the panel and pauses monitoring. Reopen uses the same panel. Quit cancels work, closes the panel and removes the menu-bar item.

## Duplicate-window cause
The previous AppDelegate already owned a single panel and reused it when switching views. However, the setup script used `open -n`, explicitly allowing another process. There was no cross-process guard, and Close intentionally collapsed to an icon rather than removing it. Multiple installed development copies were also found. These mechanisms explain persistent icons; the original reported incident was not reproduced, so its exact process count cannot be established retrospectively.

The new app holds an OS-released per-user process lock. A second updated process requests that the first show its panel, then exits. The app-level lock prevents duplicate updated instances. The Launch Services multiple-instance restriction was removed after it interfered with Xcode Run. Setup no longer uses open -n and forwards its configuration action to the existing updated app. No automatic killing of older app copies was added. Quit any already-running older copies once before testing this version.

## Files changed
- Sources/CodeCoach/Views.swift — theme, layout, companion view and pulse.
- Sources/CodeCoach/ReasoningView.swift — labels, spacing, colored hints and clearer code review.
- Sources/CodeCoach/WindowChrome.swift — light native titlebar and shared artwork loading.
- Sources/CodeCoach/Main.swift — lifecycle, single-instance guard, menus, cleanup and setup forwarding.
- Sources/CodeCoachCore/Reasoning.swift — user-facing missing-setup message only; provider and Keychain identifiers unchanged.
- Sources/CodeCoach/Resources/Companion.png — new transparent artwork.
- AppIcon.icns — replacement app icon.
- Package.swift and CodeCoach.xcodeproj/project.pbxproj — bundle artwork in every build path.
- Info.plist — multiple-instance restriction.
- scripts/build-app.sh — copy artwork into app bundle.
- scripts/configure-deepseek.sh — stop explicitly launching extra instances.
- scripts/DrawIcon.swift — package the supplied artwork instead of drawing the old braces icon. Usage: `swift scripts/DrawIcon.swift Sources/CodeCoach/Resources/Companion.png /path/to/Companion.iconset`, then `iconutil -c icns /path/to/Companion.iconset -o AppIcon.icns`.
- This report.

## Verification
Xcode Debug build and standalone app build passed. Existing 31 core tests and 12 native window assertions passed. Light interface inspected onscreen. Full close/reopen/right-click and simultaneous-launch interaction checks remain for manual testing; GUI automation was interrupted by a user UI change. No live AI request was sent for this visual update. Code capture, monitoring, multi-IDE support, credentials and history formats remain unchanged.

## Run
Open CodeCoach.xcodeproj, choose CodeCoach → My Mac, and press Command-R. Or open build/CodeCoach.app. Use only one of these for testing. Existing credentials remain in Keychain; no reset or reconfiguration is required by these changes.

## Artwork
Image tool prompt: remove only the white background, preserve the irregular navy outline, yellow/green panels and caret eyes, transparent PNG, minimal padding, no shadow or redesign. The tool-produced cutout is saved in Sources/CodeCoach/Resources/Companion.png. Standard macOS image conversion packages its app-icon sizes.

## Xcode launch correction
Removed LSMultipleInstancesProhibited from Info.plist because it can block the Xcode launcher when another copy is running. The app-level process lock remains. Before debugging, quit the standalone app through its menu (closing the panel only hides it), then run in Xcode. If another updated copy remains running, a second process reveals it and exits instead of creating another icon.
