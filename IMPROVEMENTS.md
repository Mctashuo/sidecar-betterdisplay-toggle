# Improvement Notes

These are follow-up improvements for the Sidecar and BetterDisplay sync script.
They are not required for the current working behavior, but would make the
automation easier to operate and debug.

## Tasks

- [x] Make virtual display state changes idempotent.

`BetterDisplay set --tagID=16 --connected=on` returns `Failed.` when the virtual
display is already connected. The script currently treats this as a normal
command result in some sync loops, which adds noise to the log and can make
debugging harder.

Suggested direction:

- Detect whether the virtual display is already connected before calling
  `--connected=on`.
- Or treat the known "already connected" failure as non-fatal.
- Apply the same principle to repeated `--connected=off` calls if needed.

- [x] Use a three-state external display probe.

`has_external_display` currently returns only true or false, but the real system
state can be more nuanced:

- `present`: a real external display is confirmed.
- `absent`: no real external display is confirmed.
- `unknown`: probes failed or returned conflicting data.

Suggested direction:

- Only auto-connect the BetterDisplay virtual screen when the probe is clearly
  `absent`.
- Keep the current state unchanged when the probe is `unknown`.
- Log the probe result explicitly.

- [x] Add probe-source logging.

The script now combines several detection sources:

- `ioreg` active physical timing.
- BetterDisplay display identifiers plus DDC capability checks.
- `system_profiler` fallback when `ioreg` has no framebuffer data.

The log currently records the final decision but not which source produced it.

Suggested direction:

- Log messages such as:
  - `External display detected from ioreg active timing`
  - `External display detected from BetterDisplay DDC`
  - `No external display detected; ioreg stale and DDC unavailable`
  - `External display probe unknown; leaving virtual display unchanged`

- [ ] Avoid repeated BetterDisplay set calls in sync.

The sync job runs every 10 seconds and may repeatedly call BetterDisplay with
the same target state.

Suggested direction:

- Track the last requested virtual display state.
- Only call BetterDisplay when the desired state changes.
- This should reduce log noise and unnecessary BetterDisplay CLI work.

- [ ] Separate Sidecar and virtual display state files.

The current state file tracks Sidecar recovery state, for example
`external-sidecar` or `recovered`. It does not separately track the desired
virtual display state.

Suggested direction:

- Keep Sidecar state in one file.
- Track virtual display target state (`on` or `off`) in a separate file.
- Use the virtual target state to make sync behavior easier to reason about.
