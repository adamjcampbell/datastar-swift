# 0002 — ADR alignment

**Shipping version impacted:** breaking revision of `v0.1.0-alpha.1`.

## Context

Only tagged release is `v0.1.0-alpha.1`. The Datastar SDK ADR (`sdk/ADR.md` in starfederation/datastar) is the source of truth for API shape, type names, parameter defaults, wire-format field order, and request-side signal extraction. A formal audit against the ADR surfaced gaps across naming, shape, and behavior — enough that piecemeal patches would drift further, so we resolved them in one pass as a breaking alpha-to-alpha revision.

## Philosophy

**ADR-first.** The ADR is new; some older reference SDKs (notably Rust) pre-date it and have known deviations. datastar-swift takes the ADR at face value so the SDK can "speak the same language" as other Datastar SDKs going forward. Rust's shape is informational; it does not justify skipping an ADR MUST. Swift-idiomatic sugar is welcome *on top of* the ADR-literal core, not as a replacement for it.

## Decisions

### Go-style active generator

The ADR models `ServerSentEventGenerator` as a type constructed with the HTTP response, whose methods *perform* SSE operations (Go: `g := datastar.NewSSE(w, r); g.PatchElements(...)`). We mirror that semantic with a move-only (`~Copyable`) generic `ServerSentEventGenerator<Writer>` in the `Datastar` core module. The generator owns its writer by value and exposes `mutating` methods; a stored `sink` function-value `(inout Writer, ArraySlice<UInt8>) async throws -> Void` encodes the per-transport write action. Framework adapters specialize the generic — `DatastarHummingbird` binds `Writer == any ResponseBodyWriter` via a convenience `init(_:)` that writes through Hummingbird's response-body writer. User code is identical regardless of which transport is bound. (See the postscript for the history of earlier sink-closure attempts and why the generic direction is the one that stays.)

### Nested `Options` on each payload type

The ADR signature is `PatchElements(elements?, options?: {selector?, mode?, ...})` — a distinct options object. Rust flattens all fields on the top-level struct; we take the ADR-literal direction here. Each payload type (`PatchElements`, `PatchSignals`, `ExecuteScript`) has a nested `Options` struct with all optional fields; the top-level init is `init(_ elements: String = "", options: Options = .init())`. The call site reads exactly like the ADR:

```swift
DatastarEvent.PatchElements(
    "<div>Hi</div>",
    options: .init(selector: "#msg", mode: .inner)
)
```

Flat-kwargs factories (`DatastarEvent.patchElements(_:selector:mode:...) -> DatastarEvent`) remain as Swift-idiomatic sugar that internally constructs the same `Options`.

### `[String]` attributes on `ExecuteScript`

The ADR types `attributes?: []string` — an ordered list of raw attribute strings. Our previous `[String: String]` shape could not represent boolean attributes (`defer`, `async`) and diverged from the ADR. The switch to `[String]` matches Go/TS, preserves order, and admits bare attributes. The wire builder joins entries with a single space; `autoRemove` still injects `data-effect="el.remove()"` when no existing attribute starts with `data-effect=`.

### Method-aware `Request.datastarSignals`

ADR MUST: route by HTTP method — GET/DELETE from `?datastar=<json>`, POST/PUT/PATCH from JSON body. The split "sync-query vs. async-body" helpers are collapsed into one async `datastarSignals(as:context:decoder:)` that dispatches internally. Matches Rust's `ReadSignals<T>` extractor and Go's `ReadSignals`.

### `Connection: keep-alive` header

ADR MUST for HTTP/1.1. `Response.datastarSSE` now sets all three mandated headers: `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`.

### Retry omitted at default

ADR wire format: "omit `retry:` when equal to the default (1000 ms)". Previously we omitted only when `nil`; now a small `Duration.omittingSSERetryDefault` helper returns `nil` for `.milliseconds(1000)` at the event-to-wire seam.

## Intentional language-idiomatic deviations

- **Method names on the generator are camelCase (`patchElements`), not PascalCase (`PatchElements`).** Swift API Design Guidelines use camelCase for methods; the ADR writes PascalCase because Go uppercases exports. Type names (`ServerSentEventGenerator`, `PatchElements`, `PatchSignals`, `ExecuteScript`) stay PascalCase to match the ADR literally.
- **`Response.datastarSSE` doesn't take a `Request` parameter.** Hummingbird route handlers already bind the request in scope; threading it through the response factory would be pure ceremony. The ADR's "constructor accepts Request and Response" semantic is satisfied by the route handler itself.

## What we did not add

- A literal `send(eventType:dataLines:options:)` — the ADR treats `send` as an internal detail; our seam is `toWireEvent() -> SSEEvent` (public on every payload struct) + `SSEEncoding.encode(_:)` (public). Framework adapters and forward-compat for new event types are both served.
- Go-style `RemoveElement` / `Redirect` / `MarshalAndPatchSignals` convenience helpers — these aren't in the ADR and introduce two-way paths. Removals are expressible via core events in one line.

## Verification

Test suites:
- `DatastarEvent wire format` — goldens for each operation, including retry-default omission and boolean-attribute rendering.
- `Constants ↔ canonical JSON parity` — spec drift protection against `sdk/datastar-sdk-config-v1.json`.
- `ServerSentEventGenerator<Writer> generic path` — exercises the core generic generator with a non-framework in-memory collector.
- `Response.datastarSSE` + `Request.datastarSignals` — Hummingbird adapter tests via `Application.test`, including all three ADR response headers and per-verb dispatch.

## Postscript — generic generator, no @unchecked Sendable, drop DatastarStream

A second pass reshaped `ServerSentEventGenerator` again. The sink-closure design made the Hummingbird adapter reach for a `WriterBox: @unchecked Sendable` class to satisfy the Sendable sink while capturing a non-Sendable `any ResponseBodyWriter`. That's exactly the concurrency hole the Swift 6 compiler is trying to prevent — we shouldn't lie to it.

**What changed.** `ServerSentEventGenerator` is now generic over its writer and move-only: `public struct ServerSentEventGenerator<Writer>: ~Copyable`. It stores the writer by value and exposes `mutating` methods; a stored function-value `sink: @Sendable (inout Writer, ArraySlice<UInt8>) async throws -> Void` encodes the per-transport write action. The generator conforms to `Sendable` conditionally on `Writer: Sendable`. The `~Copyable` constraint enforces unique ownership of the writer — a single response-body writer can't be accidentally duplicated into two live generators emitting concurrently — and aligns with Hummingbird's own `consuming`-style writer contract.

`DatastarHummingbird` specializes `Writer == any ResponseBodyWriter` via a convenience `init(_:)` that supplies a sink calling `writer.write(ByteBuffer(...))`. `Response.datastarSSE` threads the generator through as `inout`, mirroring Hummingbird's own `ResponseBody { writer in ... }` shape — no class box, no `@unchecked Sendable`, no `Task` wrapper. Writer mutation flows `inout` all the way from Hummingbird into `sse.writer` and back out to `finish()`.

**Why the previous sink-closure design couldn't survive this goal.** Sendable's check is on captures, not parameters. A closure that *captures* `any ResponseBodyWriter` to use as a sink has to be `@unchecked Sendable` because the writer isn't Sendable. A closure that only *receives* the writer as an `inout` parameter is fine — no capture, no check. Switching from "sink captures writer" to "generator stores writer + sink operates on it as a parameter" is what makes the Hummingbird adapter concurrency-clean.

**Dropped.** `DatastarStream` product and the `swift-async-algorithms` dependency. The stream wrapper was a hand-rolled rendezvous primitive layered on the sink closure; with the writer-owning design, any consumer (Hummingbird, a future Vapor adapter, a custom NIO bridge) just provides its own specialization. Users who want a framework-agnostic `AsyncSequence<ArraySlice<UInt8>>` can wrap the generator around a trivial collector writer — see `Tests/DatastarTests/GeneratorGenericTests.swift` for a working example.

**Also dropped.** The `NonisolatedNonsendingByDefault` upcoming feature (SE-0461) on both targets. It conflicted with calling `@concurrent` methods on the Hummingbird writer from inside our async sink — the default isolation disagreement produced `sending` / data-race diagnostics. The feature added no value for this package (we don't have actor state where the default flip would help); removing it keeps async semantics aligned with Hummingbird's conventions.
