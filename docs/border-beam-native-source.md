# BorderBeam native source and ownership

DynamicIsland uses the official MIT Libraries.dev BorderBeamKit implementation
at revision `d06640864eb4adc2fe240f899a44ee6210779782`, corresponding to the
`border-beam` 1.4.1 package. Inspected sources:

- [Public reference](https://libraries.dev/beam.html)
- [Official SwiftUI package](https://github.com/Jakubantalik/Libraries.dev/tree/d06640864eb4adc2fe240f899a44ee6210779782/packages/border-beam/ports/ios/BorderBeamKit)
- [Official shader](https://github.com/Jakubantalik/Libraries.dev/blob/d06640864eb4adc2fe240f899a44ee6210779782/packages/border-beam/ports/ios/BorderBeamKit/Sources/BorderBeamKit/BeamShaders.metal)
- [MIT license](https://github.com/Jakubantalik/Libraries.dev/blob/d06640864eb4adc2fe240f899a44ee6210779782/packages/border-beam/LICENSE)

The original shader and generated `beam-spec.json` are bundled unchanged apart
from source attribution comments. The MIT notice is bundled alongside them.
The Swift preset decoding, color-filter matrices, line keyframes, pulse
oscillators and layer construction are adapted from the official SwiftUI port.
All five sizes and all four public palettes use the upstream tables. This is
not an AngularGradient stroke or a substitute pulse animation.

The upstream package requires Xcode to compile its SwiftUI stitchable shader.
Plain SwiftPM does not compile that resource, and this machine's Xcode reports
its separately downloadable Metal compiler is missing. DynamicIsland instead
uses macOS's built-in Metal runtime compiler once per process, with two thin
fragment entry points that call the original shader functions. At compilation,
the SwiftUI `stitchable` entry attribute is adapted to `static inline` so an
ordinary fragment pipeline links the functions directly; no equations change.
MetalKit views
are draw-on-demand and have no display link. A local 30 Hz TimelineView updates
the decoration without publishing into the agent store or transcript model.
Each surface reuses three bounded uniform-buffer banks and bounds GPU work to
three in-flight commands; compilation is shared by every Beam.

Visibility, explicit pause, activity and actual Reduce Motion stop the clock.
Pause/resume keeps accumulated time and discards catch-up time. Unlike upstream,
Reduce Motion applies to every family, not just pulse. Upstream 0.6 s activation
and 0.5 s deactivation fades remain intact; these effect fades have no matching
panel-motion token in transitions-dev/transitions-polish. Decorative layers do
not receive pointer events or add accessibility elements. The caller supplies
real normalized activity; the renderer never interprets transcript text.

If runtime Metal compilation or device availability fails,
`BeamMetalDiagnostics.failureDescription` reports the actual error. A missing
renderer must not be presented as a successful fidelity review.

Remaining distinctions from the browser reference are the official native
port's rounded-corner wrapping for line/pulse-inner blobs, native compositing
and rasterization, and macOS's rendering of blurred MetalKit surfaces. These
require a visual review; matching source equations alone is fixture evidence.
