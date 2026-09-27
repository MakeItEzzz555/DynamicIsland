# Agent Interaction and Live Activity Phase Summary

- Implementation SHA: `0ecd146f700a2904af2f708b7f668e41858e63d8`
- Branch: `feature/agents-ui-overhaul`
- Pull request: #18 remains open as a Draft and was not merged.
- Approval-control architecture: A dedicated authenticated Codex `PermissionRequest` route uses exact session/request correlation, generation checks, bounded expiry, replay protection, and one-shot resolution. Generic and Claude producers remain observation-only.
- Approve/Deny behavior: Approve returns the official Codex `allow` decision; Deny returns the official `deny` decision. Timeout, shutdown, expiry, or transport failure returns no decision so Codex can retain its native prompt. Infrastructure failure never auto-approves.
- Activity feed: The expanded dashboard now uses a bounded three-to-six-row structured mini-CLI timeline with meaningful tool classification, completed-operation aggregation, and explicit active operations.
- Command privacy: Display text prefers provider descriptions and otherwise uses bounded sanitized previews. Secrets, credentials, environment values, authorization headers, raw output, hidden reasoning, and full paths are excluded.
- Usage: Usage identity now includes metric and scope, allowing trustworthy sourced five-hour and weekly quotas to coexist while retaining the freshest value per scope.
- Keychain prompts: The app performs one Keychain read per bridge start. Helpers receive derived ephemeral keys and do not read Keychain. The likely cause of duplicate prompts is Keychain ACL/signing-identity churn between debug, ad-hoc, and packaged builds. Keychain storage and HMAC authentication were not weakened.
- Tests: 683 executed, 1 skipped, 0 failures.
- Validation: Debug and release builds passed; packaging succeeded; all three helper signatures and the deep app signature passed strict verification.
- Screenshots: Seven deterministic agent UI snapshots were refreshed.
- Remaining manual checks: Confirm native Codex approval continuation and Keychain prompt behavior using a consistently Developer ID-signed installed build.
