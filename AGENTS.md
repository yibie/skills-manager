# Repository Agent Instructions

## UI and interaction work

Before reviewing or changing any user-facing UI, read these in order:

1. [`docs/ui-domain-knowledge.md`](docs/ui-domain-knowledge.md) — product
   semantics, macOS conventions, accessibility constraints, and usability
   principles that define what "correct" means.
2. [`docs/ui-interaction-review.md`](docs/ui-interaction-review.md) — the
   state matrix and live-interaction procedure used to verify the result.

Project semantics and accessibility requirements are hard constraints. Apply
platform conventions next, then general usability heuristics; never use visual
taste to override a higher-priority constraint.

The live-window and state-matrix checks in the interaction-review document are
completion gates. Component previews and off-screen snapshots are supporting
evidence only; they must not be used alone to declare a UI complete.
