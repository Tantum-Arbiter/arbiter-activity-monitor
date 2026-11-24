---
status: active
owner: Sir Luke
phase: build
---

# arbiter-activity-monitor — product, UX and measurement specification

The latest operator instructions restore reference-matched Agent Orchestration and direct Claude/Codex sessions alongside the machine-performance brief. The product name remains **arbiter-activity-monitor**. Build a native SwiftUI utility, not an Electron shell or a screenshot simulation. Read actual hardware capacity; do not assume the reference's 36 GB, the initial 32 GB context, or the revised target's 24 GB. No administrator requirement, remote telemetry export, credential access, process termination or network service. User-authorized lifecycle hooks provide local metadata-only execution events.

## A. Screenshot anatomy and product interpretation

Reference canvas: approximately 1586 × 992 px. Geometry describes relationships, not a fixed-size layout.

| Region | Approximate geometry | Visual hierarchy and revised purpose |
|---|---|---|
| Status header | y 0–54, full width | Identity left; health and six compact metrics right. Persistent, actionable CPU/GPU/memory/battery/thermals. Native traffic lights remain native. |
| Navigation rail | x 0–151, below header | 9–13 line-icon destinations; cyan/violet selected capsule, fine separator, footer live state and uptime. Collapse to icons at narrow widths. |
| Resource cards | x 162–621, y 68–455 | Panel heading, dense 2-column grid, cyan CPU, purple memory, green battery. Values dominate labels; secondary readings stay muted. |
| Holographic instrument | x 633–1040, y 68–455 | Largest visual anchor, concentric arcs and computer silhouette. CPU outer arc, memory inner arc, illuminated wire globe and laptop on a projected floor. GPU availability is explicit in its resource card. Decorative geometry has no implied measurement. |
| Local workloads | x 1054–1578, y 68–455 | Up to five real Claude/Codex session rows, identified by app/model/session ID. CPU/RAM are explicitly shared app totals; models/tokens come from metadata. |
| Correlated history | x 165–995, y 470–635 | Wide, low chart, shared time axis, percent-only curves. Throughput receives separate byte/s charts. |
| Resource heatmap | x 1008–1321, y 470–635 | Aligned, labelled observations; hover value/time; missing data is dark. Each row's unit and scale are explicit. |
| Throughput card | x 1333–1578, y 470–635 | Agent Throughput shows recorded turn completions/minute; absent hooks show unavailable, never fabricated jobs or success. |
| Process explorer | x 165–621, y 649–962 | Overview top consumers; full screen searchable/sortable inventory and inspector. Revised scope explicitly reinstates process names. |
| Dependency tree | x 632–1179, y 649–845 | Agent Orchestration uses the reference's branched layout: session input → Claude/Codex → model/tools/subagents → response/output. Process ancestry remains in Workloads. |
| Timeline | x 632–1179, y 845–962 | Execution Timeline uses actual lifecycle event times; absent events show a connection state. |
| Alerts and events | x 1192–1578, y 649–962 | Severity icon + text + timestamp. Show pressure transitions and collector failures, not fictional job completions. |

The application is named **ARBITER Activity Monitor** in its header, window and bundle metadata. On launch the window fits its own display’s visible area (12-point inset, up to 1920 × 1200); display changes constrain it to the new usable area. Users can still resize normally. Wide content (1140+ points) uses three columns with height-aware rows, medium content (940–1139) uses two columns, and compact content stacks. Navigation collapses below 980 window points and the header compacts below 1440. Nodes/text retain minimum readable sizes; short screens scroll instead of clipping. Orchestration uses a 156-point graph with 40-point nodes in three separated lanes. All sizing uses local view/window geometry.

## B. Design system

Reuse ARBITER's established tokens in `arbiter-mission-control/static/style.css`: background `#080f1e`, panel `#0c1929`, text `#d8eef8`, secondary `#78a8bc`, cyan `#20f4ff`, green `#00ff88`, amber `#ffbb22`, critical `#ff2255`. Memory violet `#b388ff`, GPU blue `#388bff`, workload magenta `#ef45f8`. Revised reference tokens are starting values; existing brand continuity takes priority.

Native SF typography: identity 18–22 semibold; panel titles 14 semibold; metrics 23–46 rounded/tabular; body 12–13; supporting labels 10–11, never shrink key values to fit. Spacing 4/8/12/16/24; panel radius 14; nested card 9; 1-point cyan border at 18% opacity. Opaque layered navy gradients create glass depth without full-window blur. A restrained cyan radial glow belongs behind the instrument only. SF Symbols, no emoji. Values never rely on hue alone.

## C. Component inventory

- App shell: native titlebar, metric header buttons, destination rail, selected state, adaptive column composition, scrolling content.
- Metric card: icon, title, value/unit, measurement time/source tooltip, sparkline, range average/peak, unavailable/paused state, navigation action.
- Instrument: selectable CPU and unified-memory readouts, measured utilization arcs, cached wire globe/laptop/floor geometry and a separate rotating decorative orbit. Unsupported GPU remains an unfilled gauge in the resource matrix.
- Charts: line/area percent history; separate throughput plot; range picker; series toggles; crosshair/selected-time label; hoverable heat cells.
- Tables: search, scope and sort controls; identity = PID + start time; pin control; row inspector; accessible numeric columns.
- Workload card/tree: root identity, process count, aggregate CPU/RSS/read/write, measured descendants, explicit tracking control, attribution caveat.
- Diagnostics: health pill, memory pressure, swap growth, compression, thermal state, source availability, monitor overhead.
- Alerts: severity, first/last observation, active/resolved state, acknowledgement, dismiss/reveal controls, metric navigation.
- Settings: sampling, retention, thresholds, reduced motion, source explanations. Menu-bar summary opens the dashboard.

## D. Motion specification

| Element | Trigger/data dependency | Timing/easing | Transformation | Reduced motion / cost |
|---|---|---|---|---|
| Hover/focus | Pointer or keyboard focus | 140 ms ease-out | Border/background opacity | Instant; no timer |
| Card/button | User selection | 100 ms ease-out | Press tint | Instant; no layout transform |
| Instrument / card gauges and bars | New measured utilization | 650 ms ease-in-out | Isolated Core Animation strokeEnd, from current presentation value | Immediate when paused, hidden, low-power or reduced motion; up to 30 fps during transition |
| Metric text | New measurement | Immediate | Stable tabular replacement | Same; avoids continuous text layout |
| Navigation | User-selected destination | Immediate | Bright cyan/violet selected capsule | Same; preserve selection |
| Plot | New sample | No full-series morph by default | Append stable-ID sample | Same; bounded points |
| Pressure event | New warning/critical state | 200 ms ease-out | One-time border/tint change | Instant; no repetitive pulse |
| Session edge | Recorded running/tool event | 2.3 s compositor travel | Light follows orchestration connectors | Static when idle, stale, paused or reduced motion |
| Ambient instrument | Enabled by default per operator request | 75 s linear revolution | Cached Core Animation orbit/tick layer | Off when inactive, paused, Reduce Motion, low power or serious/critical thermal state |

The operator's visual-alignment request enables the ambient orbit by default. Brighter radial glows, cyan/violet/magenta edges, a 36-second rotating 3-D wire mesh with pulsing nodes, morphing waves, expanding floor projection, gradient-filled traces with moving glints and hover illumination reproduce the reference's effects with native vector composition. Measured arcs animate at each UI publication; displayed numeric values remain exact current observations. Ambient layers request 6–10 fps with a bounded cache of interpolated sphere/wave keyframes; static shadows stay outside animated content. The 30/150-point cyan background grid matches Mission Control’s grid spacing. No random telemetry; orchestration travel requires recorded execution state; the static reference cannot establish exact motion timing, so the timing above is an implementation decision. No dashboard-image background, custom Metal renderer or full-window blur pass.

## E. Interaction/state matrix

| Component | Hover/focus | Click/keyboard | Data states |
|---|---|---|---|
| Header/card/ring | Source, time, units; border highlight | Open detailed resource destination | Loading —; unavailable explanation; paused badge with frozen timestamp |
| Sidebar | Brightened label, visible focus | Select; native tab/space navigation; shortcuts | Persistent selection, no fake disabled destinations |
| History | Crosshair shows measured time/value | Range/series selection | Empty explanatory state; gaps stay gaps; no interpolation across sleep |
| Heat cell | Actual value + time | Resource navigation | Missing readings have distinct dark cells |
| Process row | Identity/source help | Inspect, pin; explicit tracking from inspector | Exited PID+start cannot silently become another process |
| Workload tree | Root and attribution method | Inspect node | Reparented children not guessed; unobservable children excluded |
| Alert | Severity and observation interval | Acknowledge/dismiss, navigate to resource | Resolved entries preserved; unsupported source not "healthy" |
| Settings | Descriptive labels | Native controls | Validation/clamping; changes apply without restart |

## F. Data-to-visual mapping and semantics

| Measurement | Source / calculation | Availability and interpretation |
|---|---|---|
| System CPU, user/system/idle | Mach host tick deltas / all tick deltas | 0–100% of entire machine; warmup/reset unavailable |
| Per-core CPU | `host_processor_info` delta per logical core | Core indexes are observable; do not guess P/E identity from ordering |
| P/E topology | `hw.perflevel*.name/logicalcpu` sysctl | Show counts when accessible; per-cluster utilization needs verified mapping |
| Used/wired/compressed/cache | Mach VM page counters × host page size | Used is approximation excluding file cache/purgeable; differs from Activity Monitor accounting |
| Pressure | kernel pressure level; dispatch pressure fallback if needed | Normal/elevated/critical; missing is unknown, not normal |
| Swap | `vm.swapusage`, VM swapin/out page deltas | Bytes and byte/s; no claim that swap occupancy alone means active thrashing |
| Process resources | libproc BSD/task/rusage | CPU one-core scale may exceed 100%; RSS sum can double-count shared pages; denied counters unavailable |
| Disk throughput | IOKit block-storage-driver statistics deltas | Capability tested; physical-device totals, no fabricated disk busy % |
| Process disk | rusage diskio read/write deltas | Kernel-accounted disk I/O, not all logical file operations |
| Network | 64-bit physical `en*` interface counters | Bytes/s, total bytes, interface labels; exclude VPN/loopback to avoid double count; per-process unavailable |
| Battery | IOKit internal power source capacity/source | Charge, external-power vs discharging; drain estimated from ≥60 s observations, explicitly estimated |
| Thermal | `ProcessInfo.thermalState` | Pressure classification, never degrees Celsius or fan RPM |
| GPU | IOKit AGXAccelerator PerformanceStatistics | Driver device/renderer/tiler %, GPU shared memory; capability tested on this Mac, missing fields unavailable, no sudo/helper |
| Agent sessions | Allowlisted Codex SQLite / Claude session metadata + lifecycle hooks | Model, identity, tokens, parent links and recorded execution events; no conversations or model inference |
| Sensors | Separate optional adapter boundary | Temperature, fan and power unavailable; no sudo/powermetrics daemon |
| MLX runtimes | Mapped library names of the user's Python interpreters via `PROC_PIDREGIONPATHINFO` | Presence of the MLX runtime only (`libmlx.dylib`, `mlx/core.*.so`); model, tokens and task state unavailable; no arguments, environment or file contents |
| Observed harness | Session PID (Claude metadata, MLX detection) + parent/child process links + lifecycle events | Harness process tree, reported tools and subagents; hover facts and Session inspector; no inferred stages, no conversation content |
| Updates | GitHub release feed over HTTPS, on request or opt-in daily | Latest version tag and asset checksum; download verified by SHA-256, bundle identifier, version and code signature before an in-place swap; nothing sent about the Mac |
| Workloads | Executable roots + nearest observed parent chain | Detect Codex, Claude, Ollama, MLX, Blender, Python, Node, FFmpeg, VS Code; explicit PID+start tracking can override grouping |
| Health | Memory/thermal state plus sustained CPU saturation | Critical only for critical memory/thermal; busy CPU alone at most Under Pressure; incomplete readings Unknown |

## G. Screens

Overview retains screenshot geometry, live header, resource cards, central instrument, top workloads, correlated plots, heatmap, top consumers and alerts. CPU shows total/user/system/idle, per-core charts, topology counts and consumers. GPU shows measured device/renderer/tiler utilization and reported shared-memory allocations, with driver-source limitations. Memory shows composition, pressure, compression, swap rates and memory-heavy processes. Storage shows capacity, driver byte/s and IOPS when supported. Network shows interface totals and separate up/down rates. Battery shows charge/source and observed charge history, never invented runtime. Thermals shows actual state and events with optional sensor boundary.

Processes is a searchable, sortable inventory with CPU, RSS, threads, I/O, PID/parent, state/lifetime and an inspector exposing local path, ancestry and recent observations. Workloads aggregates roots and descendants; explicit tracked roots are session-only and PID-reuse safe. History offers 1m/15m/1h/24h/7d with bounded downsampling and independent throughput charts. Alerts exposes state transitions and adjustable thresholds. Settings explains sampling/retention/permissions/privacy and the monitor's measured overhead. Menu bar exposes health, CPU, memory, battery and top accessible process.

## H. Architecture, build order and acceptance

Swift 6 + SwiftUI + Charts; small C boundary for Mach/libproc/IOKit. Actor-isolated collector, one coordinated polling loop, UI publication on main actor. No shell polling, package dependencies, daemon, cloud account or privileged helper. Process inventory every 2 s; core counters every 1 s by default; overview display publication every 4 s, details every 2 s; battery/thermal data should be cached at 10 s; inactive 15 s, constrained ≥10 s. Monotonic rate intervals; wall clock only for display/history. Bound current history and per-process observations. SQLite stores aggregate system metrics, throttled transactions, seven-day default, downsampled queries; never persists executable paths, arguments, prompts or credentials.

1. Verify collector semantics, counter resets, PID reuse, denied data and attribution with tests.
2. Deliver shell, cards, instrument, charts, details and local .app bundle.
3. Add process inspector, automatic/explicit workload grouping and measured I/O.
4. Add SQLite history, pressure events, configurable thresholds and menu bar.
5. Measure release collector and full-window overhead; inspect wide/narrow windows, keyboard access and reduced motion. Document gaps honestly.

Targets, not promises: mean idle CPU <2% of one core; standard overview RSS <150 MB; bounded history; no sustained growth. Validate native counter values against same-time system utility observations; full Activity Monitor parity is not assumed. Capture release CPU/RSS and collector timing; a short run cannot certify long-duration stability. Acceptance requires real data and truthful unavailable states, source/time help, working navigation, no fake workflow metrics, graceful optional-source failure, successful strict Swift build and meaningful tests.

Advanced follow-up acceptance: verified P/E per-core mapping; additional GPU hardware/sensor adapters; per-process network if a supported source becomes available; seven-day period comparisons and peak-preserving aggregation; event-to-history deep links; historical process evidence with explicit privacy consent; Instruments trace and prolonged soak. These must remain explicitly identified if not implemented.

## Primary references

- [Apple: SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)
- [Apple: app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Apple: thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- Installed macOS SDK headers: `mach/host_info.h`, `mach/processor_info.h`, `libproc.h`, `sys/resource.h`, `IOKit/ps/IOPowerSources.h`, `IOKit/storage/IOBlockStorageDriver.h`.

## I. Visual snapshot review

The screenshot is a design reference, not a source of measurements. Three review passes corrected panel geometry, workload row overflow, the central laptop scale, selected navigation glow, history area fills, and the populated event-column height. Review at the supplied 1586 × 992 aspect ratio, and separately at 900-point width. The runnable UI retains native scrolling when the display is shorter than the reference.

`--snapshot /absolute/path.png` renders the same overview components at reference size with real recent aggregate history and four new native samples. `--compact` renders the reflowed layout at 900 × 2800. Optional `--width` / `--height` arguments exercise other viewports. Snapshot mode freezes ambient motion and does not overwrite preferences; its traffic-light circles stand in for native window chrome, which SwiftUI's content renderer cannot capture. Real window interaction and motion are checked separately. Generated captures stay in ignored `dist/`.

Visual fidelity is assessed against layout, palette, contrast, density, vector geometry and effects. It is not a claim of pixel-identical artwork: the globe is native geometry, telemetry varies, app names are observed, and unreported agent/task/driver metrics remain explicitly unavailable.

## J. Latest alignment corrections

Agent Orchestration must never be substituted by Workload Dependencies on Overview. AI Agents displays direct Claude/Codex sessions with app/model breakdown. The original reference determines layout, neon treatment, wave/projection effects and connector composition; live data determines values and execution state. Local hooks for all AI workspaces were explicitly authorized. The reference is a still image, so timing is specified here rather than claimed to be recoverable from the image.

Motion uses compositor-backed layers, not a SwiftUI per-frame dashboard timer: orbit 75 s; travelling wave cycle 9 s; 3-D mesh rotation 36 s; projection ring 3.6 s; trace light 4.5–7 s; active session connector light 2.3 s. All ambient effects honor pause, app inactivity, Reduce Motion, Low Power Mode and serious thermal pressure. Read-only GPU sampling stays on the collector actor; session metadata reads are bounded/throttled.

## K. Session decluttering

Running, waiting and error sessions stay expanded. Idle, ended and stale sessions collapse into an Inactive group; activity-unconfirmed metadata gets a separate collapsed group. Counts and app breakdown remain visible. Both groups can be expanded, scrolled and selected. No unknown session is falsely classified as idle. Orchestration defaults to a current active session and offers an explicit Follow active session option.

## L. Reactive effects direction (2026-11-04)

Balanced is the default visual intensity: 36-second depth rotation, 500 ms gauge transitions, brief sample-edge highlights, isolated newest-sample chart highlights and event-justified connector particles. Minimal removes ambient motion and telemetry transitions. Balanced also includes the explicitly requested animated sidebar ribbon. Cinematic adds other travelling waves, grid shimmer and decorative trace glints. All modes respect Reduce Motion; low-power and serious thermal states suppress effects. Increased Contrast strengthens panel borders and removes atmospheric status tint.

Resource hover spotlights its CPU/GPU/memory series. Memory pressure and low storage use amber instead of energetic cyan. Recent events and the event list offer replay: all History charts share a ±2-minute retained-data window, with a marked event timestamp and an explicit return-to-live action. No retained data produces an empty explanation. Process inspection retains observed relationships and per-process history; no resource allocation is inferred.

Remaining validation: sustained frame pacing at 60 Hz, isolated GPU/energy attribution, and VoiceOver/full-keyboard focus coverage require dedicated profiling. Chart updates retain measured paths and illuminate the newest sample; whole-chart crossfades were removed after overhead measurement.

Sidebar particles: 20 bounded decorative sprites (12 synchronized strand tracers, eight ambient motes), cyan/magenta bloom, small white cores and occasional star glints. They represent atmosphere, never telemetry or agent execution. No particle spawning, accumulating lifetime state, or display-rate collection.

The sidebar now has an audio-wave silhouette: a centred, tapered bundle of mirrored oscillations, layered harmonics and swelling/settling peaks. Geometry is shared with particle paths; decorative audio styling never implies microphone access.
