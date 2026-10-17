# Action Studio — product and engineering decisions

## User hypothesis and first workflow

Target hypothesis: people preparing for technical internships save more learning material than they can turn into concrete practice. This has not yet been validated with users.

The first workflow is deliberately narrow: select 1–3 saved sources, describe a learning goal and a time budget, inspect editable action cards with citations, and explicitly confirm them onto the clothesline. Completion continues to use the original task and archive workflow.

The desktop interface, clothesline and original task system come from Hang Later. The Action Studio, agent executor, evidence model, run journal, confirmation boundary, provider adapter and their new regression checks are Qizhi additions made with AI coding assistance. Authorship of the upstream work remains attributed.

## Architecture

`SwiftUI ActionStudioView → main-actor StudyCoordinator → ActionAgent → PlanningModel / StudyDocumentReading`

`human confirmation → AppStore → TaskRepository.applyActionPlan → one atomic tasks.json replacement`

- `ActionPlanning.swift`: serializable source snapshots, passage/page locators, SHA-256 fingerprints, drafts, citations, run states and the local journal.
- `ActionAgent.swift`: bounded model/tool loop, compatible HTTP adapter and the explicit offline fixture.
- `StudyDocumentReader.swift`: selected notes, UTF-8/UTF-16 text/Markdown, HTML and extractable PDFs; bounded reads without browser login or JavaScript execution.
- `StudyCoordinator.swift`: durable checkpoints, cancellation/retry, debounced draft saves, sanitized failures, endpoint-specific Keychain credentials.
- `ActionStudioView.swift`: source selection, provider consent, progress, editable paper cards, quotation snapshots and run history.

The model receives a selected-source catalog and can call only `read_source` and `submit_cards`. Titles and source content are untrusted data. Unselected IDs and unknown tools are rejected by the executor, regardless of prompt compliance. There is no shell, file-browser, messaging or task-writing tool. Source paths are not included in the model tool result.

## Confirmation and recovery

All draft titles, outcomes, durations and citations are checked before one atomic batch write. A quote must be an exact whitespace-normalized substring of a known passage; every selected source must contribute before a generated plan reaches review. This is a textual-presence check, not semantic fact verification. The user can remove cards during review.

Draft IDs become task IDs. Replaying confirmation after a crash between task persistence and journal persistence returns existing tasks, preserving user edits and completion state. Citation snapshots remain in confirmed tasks even when the recent-run history rolls over.

The journal is local, restricted to owner access and retains the latest 10 runs. In-flight runs reopen as interrupted; retry starts a fresh model conversation over the same saved source snapshots. It does not restore the provider's private reasoning or claim to continue an identical conversation. Refreshing changed material requires starting a new plan.

The main actor is the task repository's single writer inside the application. The model executor does not write task files. This does not add cross-process transactions or solve simultaneous writes by multiple manually launched app instances.

## Bounds and privacy

- 1–3 sources; 5–120 minute budget; 1–6 drafts; positive integer durations with a bounded total.
- At most 8 model turns, 16 total tool calls and 6 calls in one response; provider response capped at 2 MB.
- Source downloads capped at 10 MB; PDF first 20 pages; at most 24 passages and 16,000 characters per source. Truncation is displayed.
- No login pages, OCR, video transcription, arbitrary web browsing or local model downloads.
- Live calls require user-selected sources and explicit send consent. The provider receives their text and the goal. API charges and retention policies depend on that provider.
- API keys are stored in Keychain per endpoint. No key, raw response body or hidden model reasoning is saved to the run journal. Provider redirects are rejected rather than forwarding credentials.
- Token counts use returned provider usage, not a price estimate; zero can mean no usage was reported. No hosted account, sync service or analytics is introduced.

## Why this implementation

The first version uses native Swift concurrency and a protocol-based model adapter. It needs no bundled Python interpreter, large model weights, persistent agent daemon or separate server. The existing native UI and single application writer remain easy to inspect. API I/O and bounded extraction do not block the main thread.

A shared hosted API, PostgreSQL, a browser demonstration and real user onboarding are later product work, not implemented features. Add them when a validated use case or full-stack demonstration needs that boundary, while keeping this agent and confirmation contract reusable.

## Proposed user study — not completed

Recruit 5–10 volunteers who already save technical learning material. Ask each to make a short plan manually, then use the same workflow with their chosen sources. Record planning friction, edits, citation issues, whether they confirm a plan, whether tasks are completed, and whether they return the following week. Keep denominators and missing follow-ups explicit. Small-sample observations are qualitative evidence, not statistically established retention gains.

Use interviews to decide whether the next feature should be better extraction, better task sizing, or a web companion. No users, retention statistics, productivity gains or willingness-to-pay results are claimed in this release.
