# Development checkpoint

The new Reasoning tab supports explicitly supplied code, manual consent, DeepSeek conceptual analysis, locally saved observations with confirm/dismiss, and three multiple-choice daily exercises saved with answers. These paths build but live AI results are unverified: no credential exists under com.stucksense.deepseek / api-key.

Configure locally by opening ../StuckSense-Developer/ConfigureDeepSeek. Then build CodeCoach.xcodeproj, select CodeCoach / My Mac, press Command-R. In Reasoning, review the sample maximum-finding code, enable consent, and send. No compiler is required for this explicit-code path. Switch to Habits to review the result and Practice to generate three questions.

New files: Sources/CodeCoachCore/Reasoning.swift, Sources/CodeCoach/ReasoningView.swift, Tests/CodeCoachCoreTests/ReasoningTests.swift. Modified: AppModel.swift, Views.swift, project.pbxproj. Existing English release preserved separately.

Incomplete: live response and logical classification validation; old-provider removal; five-section redesign; monitoring integration for additional languages; source-event identifiers; recurring-concept aggregation; practice-history input to generation; hints; code-writing/test-based exercises; demo history separation; progress trends; teammate UI comparison (reference not yet supplied). Existing README describes the prior release. This is a development checkpoint, not the final requested demo.
