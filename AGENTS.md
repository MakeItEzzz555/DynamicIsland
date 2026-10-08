## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Mandatory design and implementation skills

For every implementation prompt, including plans, component changes, and UI repairs, evaluate the installed skills before editing. Read and apply every skill relevant to the requested work; briefly identify the selected skills and validation tools. This is a standing requirement, even when the prompt does not explicitly name a skill. Select skills by their documented scope and the project's native platform rather than applying every visual style simultaneously.

Skills are installed in `.agents/skills/`; also check the current agent's global skill directory (`~/.codex/skills/` or `~/.claude/skills/`). Read the actual `SKILL.md` before applying it. A missing or incompatible skill must be reported accurately, with an appropriate available alternative.

### Native SwiftUI / AppKit application

- DynamicIsland is a native macOS app. Use applicable design principles from `redesign-existing-projects`, `high-end-visual-design`, and the taste skills for hierarchy, typography, color, spacing, interaction states, and visual review. Preserve the existing product language and native macOS conventions. `design-taste-frontend` is primarily for landing pages and portfolios; its web layouts are not a default for the island.
- For new visual concepts or screenshot-driven implementation, use `image-to-code`'s reference-analysis method and the appropriate image-generation skill where applicable. Extract geometry and interaction requirements, then implement them with real SwiftUI/AppKit primitives. Website-only image-generation requirements do not apply automatically to native runtime bug fixes. Synthetic images are design references, never evidence that the running app works.
- Translate applicable web design ideas into native implementation: layout into existing semantic layout resolvers and SwiftUI stacks/grids, typography into native font styles, controls into SwiftUI/AppKit controls, accessibility into VoiceOver/keyboard semantics, and motion into existing `WorkspaceMotion` / editor motion tokens. Honor Reduce Motion. Preserve semantic widget sizes, shell/notch geometry, generation-safe native ownership, and provider capability boundaries.
- CSS, React, Tailwind, GSAP, DOM APIs, and browser gesture recognizers are not Swift dependencies. Do not add a web view, new UI framework, duplicate layout resolver, or parallel animation engine merely to reuse a web skill. Check Swift/macOS API compatibility before translating techniques; explain an incompatible technique and use a native equivalent.
- Aesthetic-specific skills (`minimalist-ui`, `industrial-brutalist-ui`, `gpt-taste`, `brandkit`) apply when the brief calls for their style or deliverable. Use `imagegen-frontend-mobile`, `imagegen-frontend-web`, and `stitch-design-taste` only for the corresponding concept, web, or Stitch task. Preserve the user's chosen style when skills disagree.

### Swift implementation references

For every Swift implementation plan and component task, read the installed `awesome-swift` adapter and consult the relevant section of `~/.codex/design-references/awesome-swift/README.md` (`matteocrippa/awesome-swift`). It is a resource catalog with a local skill adapter, not an application package or upstream plugin. Verify candidates against their own repository/documentation for native macOS 14.6+ support, Swift 6/concurrency compatibility, SwiftPM integration, maintenance, and license. UIKit/iOS-only components are not native macOS components. Prefer existing DynamicIsland modules and supported SwiftUI/AppKit APIs; add a dependency only for a concrete, verified benefit. Preserve the existing architecture and native validation contracts.

### Web surfaces and native validation

- For an actual web surface, use `web-design-guidelines` for interface/accessibility review and Microsoft's `playwright-cli` skill for real browser interaction, screenshots, and applicable keyboard, responsive, console, and Reduce Motion checks. Use an isolated named browser session and fresh snapshot references. Do not close the user's unrelated browser sessions.
- For native DynamicIsland acceptance, use the project's Swift tests, packaging workflow, actual SwiftUI/AppKit runtime, and appropriate macOS inspection/screenshot tools. Playwright tests a browser; it does not validate native NSPanel geometry, terminal mounting, trackpad input, or Spotify playback. Do not claim physical acceptance from a mockup, static test, or browser screenshot.
- Work from audit and a compact plan through implementation to runtime inspection and correction. Use complementary tools when they produce needed evidence; report what was actually tested and any blocked live checks. Preserve active user sessions and existing permission grants.

### Source identity

`image-to-code` currently comes from `Leonxlnx/taste-skill`. Do not label it as an OpenAI plugin: `openai/role-specific-plugins` was a placeholder when checked. `awesome-design` is a local skill adapter for `VoltAgent/awesome-design-md`, installed globally at `~/.codex/design-references/awesome-design-md/`. For visual design and component work, read the adapter and a relevant collection reference, then apply compatible principles under the native rules above. The upstream source is a design-reference library, not a plugin; do not overwrite the project's design language with a brand's website layout.
