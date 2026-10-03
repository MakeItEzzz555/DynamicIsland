#!/bin/bash
# Phase-scoped validation; all generated evidence stays outside the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
output=/tmp/dynamicisland-phase3
mkdir -p "$output"
case "${1:-focused}" in
  focused)
    swift test --filter 'LibrariesNativeFidelityTests|LibrariesOrbGoldenTests|AgentVisualEffectsTests|LiveActivityLayoutResolverTests|ExpandedIslandMotionTests|MetalSendInteractionTests' > "$output/focused.log" 2>&1
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
  soak)
    DYNAMIC_ISLAND_AGENT_SOAK=1 DYNAMIC_ISLAND_AGENT_SOAK_REPORT="$output/soak.json" swift test --skip-build --filter 'AgentsPerformanceHarnessTests/testMeasureBoundedLifecycleSoak' > "$output/soak.log" 2>&1
    tail -12 "$output/soak.log"
    ;;
  release)
    Scripts/package_app.sh > "$output/package.log" 2>&1
    codesign --verify --deep --strict --verbose=2 dist/DynamicIsland.app > "$output/signature.log" 2>&1
    cat "$output/signature.log"
    ;;
  *) echo 'usage: validate_agent_visual_fidelity.sh focused|parity|full|native|codex|soak|release' >&2; exit 64 ;;
esac
