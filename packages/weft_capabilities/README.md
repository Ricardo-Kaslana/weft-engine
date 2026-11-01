# weft_capabilities

Capability gateway and policy contracts for [Weft](https://github.com/Ricardo-Kaslana/weft-engine) scripts.

A JS session sees only the capability namespaces its host enabled. This package
implements the gateway that authenticates each call, enforces the policy
(allow-list, argument schema, size and rate limits) and journals side effects so
a restarted runtime can replay state without repeating them.

## Pieces

| Type | Role |
|---|---|
| `WeftCapabilityIds` | Stable ids for the built-in `state`, `events` and `net` namespaces |
| `CapabilityPolicy` | Which namespaces and methods a document may call, plus limits |
| `CapabilityGateway` | `BridgeDispatcher` that authenticates and dispatches calls |
| `BridgeJournalEntry` | Record of an applied call, used for recovery de-duplication |

The built-in implementations (`state`, `events`, `network`) are separate
libraries in the same package so a host can wire only what it enables.

## Boundaries

- Disabled capabilities are absent from the JS namespace, not merely rejected at
  call time.
- Network access is proxied by the host: URL allow-list, redirect and response
  size checks happen on the Dart side before any bytes reach a script.
- The gateway does not decide navigation, storage or auth policy; those stay in
  host code.

## License

MIT.
