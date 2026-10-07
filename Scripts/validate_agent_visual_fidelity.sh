#!/bin/bash
# Phase-scoped validation; all generated evidence stays outside the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${2:-/tmp/dynamicisland-phase3}"
mkdir -p "$output"
case "${1:-focused}" in
  focused)
    swift test --filter 'LibrariesNativeFidelityTests|LibrariesOrbGoldenTests|AgentVisualEffectsTests|AgentProcessingSemanticTests|LiveActivityLayoutResolverTests|ExpandedIslandMotionTests|MetalSendInteractionTests|AgentStreamingTextTests|NativeMetalFxTests' > "$output/focused.log" 2>&1
    tail -12 "$output/focused.log"
    ;;
  parity)
    DYNAMIC_ISLAND_LIBRARIES_PARITY_DIR="$output/parity" DYNAMIC_ISLAND_AGENT_VISUAL_SNAPSHOT_DIR="$output/integration" DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR="$output/agents" swift test --filter 'LibrariesNativeParityTests|AgentVisualSnapshotTests|AgentUISnapshotTests/testRenderAgentUIReviewSnapshots' > "$output/parity.log" 2>&1
    tail -12 "$output/parity.log"
    ;;
  full)
    swift test > "$output/full.log" 2>&1
    tail -12 "$output/full.log"
    ;;
  native)
    DYNAMIC_ISLAND_PHASE5_SNAPSHOT_DIR="$output/phase5" DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR="$output/agents" DYNAMIC_ISLAND_AGENT_VISUAL_SNAPSHOT_DIR="$output/integration" DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR="$output/orbit" DYNAMIC_ISLAND_LIVE_ACTIVITY_SNAPSHOT_DIR="$output/sidecars" DYNAMIC_ISLAND_AGENT_PERF=1 DYNAMIC_ISLAND_AGENT_PERF_REPORT="$output/performance.json" DYNAMIC_ISLAND_LIVE_VOICE_RECORDING=1 swift test --skip-build --filter 'AgentPhase5SnapshotTests|AgentUISnapshotTests|AgentVisualSnapshotTests|AgentsPerformanceHarnessTests/testMeasureAgentsPage|FileDragOrbitSnapshotTests|LiveActivitySidecarSnapshotTests|VoiceRecordingLiveTests' > "$output/native.log" 2>&1
    tail -12 "$output/native.log"
    ;;
  codex)
    DYNAMIC_ISLAND_LIVE_AGENT_E2E=1 DYNAMIC_ISLAND_LIVE_APPROVAL_E2E=1 DYNAMIC_ISLAND_LIVE_AGENT_ROOT="$output/live-codex" DYNAMIC_ISLAND_LIVE_AGENT_PROVIDERS=codex swift test --skip-build --filter 'AgentLiveEndToEndTests/testCodexLiveEndToEnd|AgentLiveApprovalEndToEndTests/testCodexLiveDenyThenAllowThroughApprovalController' > "$output/codex.log" 2>&1
    tail -12 "$output/codex.log"
    ;;
  approval)
    # Exact user-decided deny/allow acceptance; never enables auto-approval.
    DYNAMIC_ISLAND_LIVE_APPROVAL_E2E=1 DYNAMIC_ISLAND_LIVE_AGENT_ROOT="$output/live-codex" DYNAMIC_ISLAND_LIVE_AGENT_PROVIDERS=codex swift test --skip-build --filter 'AgentLiveApprovalEndToEndTests/testCodexLiveDenyThenAllowThroughApprovalController' > "$output/approval.log" 2>&1
    tail -12 "$output/approval.log"
    ;;
  semantics)
    DYNAMIC_ISLAND_LIVE_CODEX_SEMANTICS=1 swift test --skip-build --filter 'AgentProcessingSemanticTests/testLiveCodexSemanticSequence' > "$output/live-semantics.log" 2>&1
    tail -12 "$output/live-semantics.log"
    ;;
  soak)
    DYNAMIC_ISLAND_AGENT_SOAK=1 DYNAMIC_ISLAND_AGENT_SOAK_REPORT="$output/soak.json" swift test --skip-build --filter 'AgentsPerformanceHarnessTests/testMeasureBoundedLifecycleSoak' > "$output/soak.log" 2>&1
    tail -12 "$output/soak.log"
    ;;
  performance)
    DYNAMIC_ISLAND_AGENT_PERF=1 DYNAMIC_ISLAND_AGENT_PERF_REPORT="$output/performance.json" swift test --skip-build --filter 'AgentsPerformanceHarnessTests/testMeasureAgentsPage' > "$output/performance.log" 2>&1
    tail -12 "$output/performance.log"
    ;;
  layout)
    DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR="$output/workspace" swift test --filter 'AgentCompactPermissionGeometryTests|AgentWorkspaceSnapshotTests|AgentApprovalControllerTests|AgentHoverAndComposerTests|AgentComposerReachabilityTests' > "$output/layout.log" 2>&1
    tail -12 "$output/layout.log"
    ;;
  compact-live)
    DYNAMIC_ISLAND_LIVE_COMPACT_PERMISSION=1 DYNAMIC_ISLAND_LIVE_APPROVAL_E2E=1 DYNAMIC_ISLAND_LIVE_AGENT_ROOT="$output/live-codex" DYNAMIC_ISLAND_LIVE_AGENT_PROVIDERS=codex swift test --skip-build --filter 'AgentLiveApprovalEndToEndTests/testCodexLiveDenyThenAllowThroughApprovalController' > "$output/compact-live.log" 2>&1
    tail -18 "$output/compact-live.log"
    ;;
  motion)
    DYNAMIC_ISLAND_AGENT_PERF=1 DYNAMIC_ISLAND_AGENT_MOTION_REPORT="$output/motion.json" swift test --filter 'AgentsPerformanceHarnessTests/testMeasureShellRendererHandoffs|AgentStreamingTextTests|NativeMetalFxTests|AgentWorkspaceSnapshotTests/testNativeTranscriptKeepsLatestVisibleDuringStreamingAndRespectsHistoryScroll' > "$output/motion.log" 2>&1
    tail -12 "$output/motion.log"
    ;;
  capture)
    DYNAMIC_ISLAND_LIVE_SCREEN_RECORDING=1 swift test --skip-build --filter 'ScreenRecordingLiveTests' > "$output/capture.log" 2>&1
    tail -12 "$output/capture.log"
    ;;
  camera)
    DYNAMIC_ISLAND_LIVE_CAMERA=1 swift test --skip-build --filter 'CameraMirrorLiveTests' > "$output/camera.log" 2>&1
    tail -12 "$output/camera.log"
    ;;
  release)
    Scripts/package_app.sh > "$output/package.log" 2>&1
    codesign --verify --deep --strict --verbose=2 dist/DynamicIsland.app > "$output/signature.log" 2>&1
    cat "$output/signature.log"
    ;;
  *) echo 'usage: validate_agent_visual_fidelity.sh focused|parity|full|native|codex|approval|semantics|soak|performance|layout|compact-live|motion|capture|camera|release [output-directory]' >&2; exit 64 ;;
esac
