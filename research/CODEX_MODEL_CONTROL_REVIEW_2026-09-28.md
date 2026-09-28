# Codex Managed Model Control Review — 2026-09-28

## Verified sources

- Installed/upstream Codex app-server v2 schema:
  - model/list → ModelListParams / ModelListResponse
  - turn/start → TurnStartParams
  - thread/start → ThreadStartParams
- Upstream source: openai/codex, codex-rs/app-server-protocol/schema/typescript/v2/.
- App-server README documents model/list as the provider-aware model catalog.

## Inventory

model/list is the authoritative inventory for the configured startup provider. It supports bounded pagination and includeHidden. Model records include exact id, provider model string, displayName, description, hidden, isDefault, supported/default reasoning effort, modalities, service tiers, and upgrade/access metadata.

DynamicIsland keeps exact provider model strings for requests, filters hidden entries from the user picker, uses safe display labels, bounds the catalog, and retains the last successful catalog when a transient refresh fails.

## Selection semantics

Current v2 schema states:

- ThreadStartParams.model: optional model for a new thread.
- TurnStartParams.model: override the model for this turn and subsequent turns.

For an existing thread, DynamicIsland stores a pending next-turn override and passes it to turn/start. The currently displayed authoritative model remains the provider-reported thread model until discovery/metadata confirms the change.

During an active turn or prompt submission, model changes are disabled to avoid a model/submit race.

For a new session, DynamicIsland passes the chosen provider-backed model directly to thread/start; no local session is projected until the provider accepts and returns a thread.

## Context

Model selection never invents a context-window size. Context remains selected-thread scoped and uses only provider-sourced context-window metadata. A pending model override does not reinterpret existing context usage.
