---
status: active
owner: Sir Luke
phase: build
---

# arbiter-activity-monitor

Native macOS system and AI workload monitor. Read-only except the operator-initiated Quit / Force Quit described below. Read root AGENTS.md first.

- Swift 6, macOS 14+, SwiftUI and system frameworks only. No package dependencies.
- Keep collectors off the main actor; bounded history and sampling, no shell polling.
- Never read credentials, agent conversations, command arguments, or environment variables.
- App resource attribution is distinct from model/task telemetry. Never infer model, job success, tokens, GPU usage, temperature or energy from CPU use.
- Missing measurements are unavailable, never zero or demo values. Fixtures are opt-in and visibly marked.
- Use ARBITER navy #080f1e, cyan #20f4ff, green #00ff88, amber #ffbb22 and vivid purple/magenta. SF Symbols, no emoji. The operator explicitly requested animated reference-matched effects: use isolated, inexpensive decorative orbit layers and data-driven transitions; stop ambient motion when hidden, paused, reduced-motion, low-power or thermally constrained. Decorative motion must not imply task execution.
- Direct Claude/Codex session monitoring is explicitly authorized. Read allowlisted local metadata columns/files only; never open transcripts, rollouts, prompts or credentials. The operator authorized lifecycle hooks in all local AI workspaces. Hooks emit session ID, model, event, tool name, agent ID and time only; ignore payload contents and never influence agent decisions. Codex native hook trust remains operator-controlled.
- Agent Orchestration shows the observed harness (`HarnessBuilder` in ArbiterCore): a session is linked to processes only through a PID its own metadata reports, tools and subagents only through lifecycle events. Unobserved nodes say "Not reported" with dashed links; never fill them from CPU use or app-wide totals. Hover cards and the Session inspector show the same allowlisted metadata, nothing more.
- MLX agents are detected only from mapped library names (`libmlx.dylib`, `mlx/core.*.so`) in the user's Python interpreters, bounded per pass and cached per PID+start. A detected runtime is `Loaded`, never running; model, tokens and task state stay unavailable unless an MLX agent emits allowlisted hook events as app `MLX`. Agent/runtime identity goes through `AgentApp.category` / `ProcessSample.agent`, not numeric ranges.
- The module was renamed from `arbiter-system`. The data folder `Application Support/ArbiterSystem` and bundle identifier `local.arbiter.system` are deliberately unchanged; do not rename them without a migration.
- GPU device/renderer/tiler utilization is capability-tested from AGXAccelerator PerformanceStatistics; unknown keys are unavailable.
- UI display name: ARBITER Activity Monitor. Fit the window to its attached display, reflow at local width breakpoints, and keep orchestration nodes non-overlapping. Animate measured gauges in isolated Core Animation layers; never reintroduce full-dashboard frame timers. Collapse inactive sessions separately from unconfirmed activity. Match Mission Control’s 30/150-point cyan grid.
- Tests: `swift test`; release build: `scripts/build-app.sh`. Document metric semantics and limitations in README.md and requirements.md.
- Generated `.build/`, `dist/`, runtime telemetry and screenshots stay untracked. Do not add privileged helpers, auto-start, networking or agent-log scraping without operator approval. The one approved network use is the updater in `ArbiterCore/Updater.swift` (GitHub release feed and asset download): keep it opt-in, send nothing about the Mac, and never install a download that fails the checksum, bundle identifier, version or code-signature checks.
- Process control (operator-approved): only `ProcessControl` in ArbiterCore may signal processes, only after the operator selects them and confirms the `QuitConfirmation` dialog. Re-check PID + start time immediately before signalling; never elevate; keep launchd, kernel_task, WindowServer, loginwindow, other users' processes and this monitor refused. Never quit anything automatically, from a timer, an alert or a hook event.
- Local LLM benchmark (operator-approved loopback networking): `BenchmarkRunner` talks only to `127.0.0.1` ports of local runtimes (Ollama native API, OpenAI-compatible servers). Send only the fixed built-in prompts in `BenchmarkPrompt`; never send session, file, clipboard or system data; never pull, download or load a model the runtime does not already list; run only when the operator presses Run (or the `--benchmark-llm` command). Store model names and measurements only.
- Token usage comes only from what agents report (Codex `tokens_used`); never estimate tokens from CPU, time or transcripts. Unreported is shown as Not reported.
- The version lives in `VERSION`; a release must be tagged `v<VERSION>` with the `-macos-arm64.zip` asset the build script produces, or the updater will not offer it.
- Balanced is the default visual intensity. The operator explicitly requested the sidebar ribbon in Balanced; reserve other persistent decorative waves/glints for Cinematic; prefer bounded measurement-triggered feedback. Minimal, Reduce Motion, inactivity, low power and serious thermal pressure suppress motion. Replay is a shared retained-data time window, never fabricated historical values.
