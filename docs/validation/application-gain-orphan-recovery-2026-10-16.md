# Per-app gain teardown recovery

Baseline: `6a6c53df429b08f5a1a03c744bfdf53c56349846`.
Owner: the user-facing Codex orchestrator, isolated worktree
`/private/tmp/DynamicIsland-orb-identity-20261015`.

## Confirmed defect and correction

`ApplicationGainEngine.close` retains HAL resources when destruction fails.
The session has already been removed from `sessions`, so a later `setGain`
could open another tap for the same application without retrying that cleanup.
A unity request could also return success without releasing the retained tap.

The engine now retries that application's retained teardown before creating or
updating its routing. A failed retry propagates through the existing error path.
Unity requests retry retained resources even when there is no current session.
Other applications remain independently controllable. The existing actor owns
these synchronous HAL operations; no new task, timer, dependency or audio callback
work is introduced.

## Validation

- Before the implementation, the two new regression tests failed six assertions:
  an unexpected second tap, missing teardown ordering and false unity success.
  Log: `/private/tmp/dynamicisland-orphan-before-fix.log`.
- After the implementation, `swift test --filter
  'ApplicationGainEngineTests|ApplicationGainRendererTests|ApplicationVolumeProviderTests|ApplicationAudioOwnershipTests'`
  passed 33 tests with zero failures and zero skips. This includes saved levels,
  helper-process rebuilds, concurrent slider writes, off/on ownership, independent
  applications and recovery after a persistent destroy failure.
  Log: `/private/tmp/dynamicisland-orphan-focused.log`.
- `git diff --check` passed. `graphify update .` ran; generated graph changes are
  excluded from the implementation commit. Its parser warnings concern unchanged
  `ApplicationAudioOwnership.swift` and `MediaAdvancedControls.swift`.
- Codex inspected the changed engine, all engine callers in
  `ApplicationAudioDiscovery`, teardown ordering, watchdog ownership and the
  connected provider/renderer tests using the Ponytail review workflow.

## Pending gates

Actual Claude review and integration are pending; this report is not joint
consensus. Run one isolated full suite and release/package checks on the final
integrated commit after the roadmap wave is assembled. Existing CI success for
`6a6c53d` is baseline evidence, not validation of this additional patch.

Fake HAL tests do not establish physical audio-device acceptance. A permanent
CoreAudio teardown failure can still retain resources; this patch prevents
creating another same-application route over them and enables retry on the next
gain/release request. It does not guarantee recovery from an unrecoverable OS
failure or change the controller's existing disable-error presentation.

No push, PR mutation, merge, installed-app replacement or permission change was
performed by this implementation owner.
