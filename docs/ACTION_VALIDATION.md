# Action Studio 0.2.0 validation

Validation date: 2026-10-17. Local Apple Silicon macOS build. These checks use synthetic sources, scripted model replies and a local HTTP provider. No real API key or personal source documents were used.

## Automated checks

- 22 existing core checks continue to cover persistence, completion, layout, input validation and browser identity.
- 33 new deterministic regression checks cover the multi-turn source/read/submit workflow, invalid/missing/unknown citations, invented quotes, duration and input bounds, provenance persistence, legacy decoding, atomic batch failure, replay after user edits and completion, ID collisions, interrupted/corrupt journals, snapshot retry, cancellation, model repair, unknown tools, unselected reads, turn limits, checkpoint failure and endpoint validation.
- 10 real HTTP-adapter fixture scenarios: normal tool calls, quotation repair, unselected source requests, unknown tools, 401, 429, blocked credential-bearing redirects, declared oversized response, oversized body without Content-Length, and malformed JSON. Usage parsing and tool-call result IDs are exercised through the network adapter.
- Native app check: coordinator runs an offline plan; creates no tasks before review; persists edited drafts; confirms once; rejects repeated confirmation; extracts actual HTML/Markdown and a generated two-page text PDF; retains PDF page locators; handles cancellation immediately followed by a new run.
- Existing Native Messaging host and extension identity/syntax checks remain part of CI.

Reproduce from the repository root:

```sh
bash scripts/swift.sh run HangLaterChecks
mkdir -p build
bash scripts/swift.sh run QizhiAgentChecks --report build/agent-fixture-report.json
python3 scripts/verify-agent-http.py
bash scripts/build-app.sh release
./.build/release/HangLater --verify-action-studio
```

The macOS CI runs these checks and publishes the deterministic JSON report as `Qizhi-Agent-Validation`. Check the Actions run for the commit being reviewed; this document does not substitute for its result.

## Visual checks

The source picker, human-review cards and dark mode are rendered from isolated synthetic data. Screenshot captions explicitly identify the offline sample. Paper citations, budgets, edit fields, disabled states and the sidebar were visually reviewed.

```sh
./.build/release/HangLater --render-action-preview /tmp/qizhi-studio.png --review
./.build/release/HangLater --render-action-preview /tmp/qizhi-studio-dark.png --review --dark
```

## Boundaries of this evidence

Fixture pass counts are not live-model success rates. Real provider compatibility, usefulness of generated plans, semantic support of citations, multilingual quality, latency/cost under live usage, and user retention have not been measured. A configured endpoint must support the documented Chat Completions tool protocol. Live calls fail explicitly; they do not silently return offline sample cards.

Keychain integration is implemented with Security.framework; test fixtures deliberately do not access the user's real Keychain. First-run Keychain prompts, real provider setup and real-world extraction from login/JavaScript-heavy pages remain manual checks.

Original 3D and desktop system-permission limitations remain documented in BUILD_VALIDATION.md. No original test suite or visual design is claimed as Qizhi's original work.
