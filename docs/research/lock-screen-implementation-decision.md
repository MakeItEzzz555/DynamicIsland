# Lock-screen implementation decision — 2026-10-14

**Decision: do not implement a third-party secure-lock overlay in this slice.** No SkyLight dependency, private symbol loading, altered window level, lock manipulation or secure-session test was performed.

## Evidence and uncertainty

The supplied `DROPPY_16_LOCK_SCREEN_RE_2026-10-14.md` concerns Droppy **16.0.1**. Binary type names and SLS/private-framework strings are observed static evidence; exact runtime behavior, TCC requirements and compatibility are not live acceptance. Its February-source-only lock detection/window flags must not be promoted to observed 16.0.1 behavior. The report's inferred wallpaper-color source and capability requiring no TCC grant remain inference, not authorization.

Public `NSWorkspace.sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` describe session activation changes (for example fast user switching); they do not provide an authoritative universal “screen locked” state. Sleep/wake is observable through documented workspace events. `com.apple.screenIsLocked` distributed names and the `CGSSessionScreenIsLocked` dictionary key are not a documented security contract. Do not treat them as a security boundary or use them to expose sensitive data.

Ordinary AppKit window levels/collection behaviors have no documented guarantee of drawing interactive application widgets over the secure loginwindow/lock session. A fullscreen auxiliary window is not a lock-screen widget API. No supported public lock-screen overlay mechanism was established by this investigation; this is not a claim that every future macOS integration is impossible.

## SkyLightWindow

[Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) declares an MIT license, and its upstream README explicitly describes private SkyLight APIs and susceptibility to macOS changes. MIT permits using the library subject to its notice; it does **not** make private macOS calls public or guarantee distribution approval, notarization, compatibility or safe secure-screen interaction.

The current upstream README claims Mac App Store availability. That conflicts with [Apple's App Review guideline 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements), which requires public APIs. Do not adopt the README claim as approval evidence. Direct distribution removes App Store review as a gate but does not eliminate private ABI changes, signing/notarization checks or privacy risk. No claim is made that notarization accepts or rejects this particular library.

The supplied report describes private space creation at an elevated absolute level. We did not reproduce its mechanism, load its symbols or install the library. Changing that space/window authority requires separate explicit approval and a fresh security/compatibility review. The reported snapshot predates current upstream traits, so deployment/toolchain guarantees must be pinned and independently reverified if ever approved.

## Supported independent alternative

Keep ordinary widgets on the unlocked desktop/in their existing island. Hide private widget state and stop permission-sensitive capture on documented sleep/session-inactive events. Resume private content only under ordinary desktop ownership; lack of a lock notification must not authorize showing it above a secure session. Offer inert Settings previews of placement and show timer/media information after return to an active session, clearly labelled desktop behavior. Use OS-owned notifications only through their supported API and the user's system privacy policy; do not promise lock-screen placement or delivery.

If a private experimental overlay is separately approved later, isolate it from the production panel and default it off. Its data model must be allowlisted: no clipboard, files, agent transcripts, private messages, calendar titles, participant names or sensitive artwork/metadata without a separately reviewed policy. Fail closed on unavailable symbols, unknown OS versions, session transitions and identity ambiguity. Test on explicit supported macOS/signing combinations; keep a public-API-only distribution path.

## Primary references

- [NSWorkspace session resignation](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification)
- [NSWindow levels](https://developer.apple.com/documentation/appkit/nswindow/level)
- [Apple App Review 2.5](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
- [SkyLightWindow upstream and license](https://github.com/Lakr233/SkyLightWindow)

This is a feasibility/security decision, not implementation or live lock-screen acceptance.
