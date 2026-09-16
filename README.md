# Roblox Ability Lifecycle

A focused Luau code sample by **Zachary Vanier**: the lifecycle beneath a chargeable or interruptible ability.

The runner coordinates start, hold, release, cancellation, and final cleanup. It separates that logic from input, effects, clocks, and network transport, so its behavior can be tested without starting Roblox Studio.

The two runtime modules are extracted unchanged from my VZN Framework. This repository includes their original tests, an executable charge-ability example, and the MIT license. It has no runtime package dependencies or game assets.

## Start here

1. [ChargeAbility.luau](examples/ChargeAbility.luau) — see the caller-facing API through a complete use cycle.
2. [Types.luau](src/VZNCore/Features/Behavior/Shared/Types.luau) — read the public contracts.
3. [Runner.luau](src/VZNCore/Features/Behavior/Shared/Runner.luau) — inspect lifecycle ownership and failure handling.
4. [Runner.spec.luau](tests/Features/Behavior/Runner.spec.luau) — inspect ordering, duplicate-input, replication, and nested-cleanup tests.

## Run it

With Rokit installed, run these commands from the extracted folder or repository root:

```sh
rokit install
lune run tests/Features/Behavior/Runner.spec.luau
lune run examples/ChargeAbility.luau
```

The original suite contains five cases. The example asserts normal release, repeated input, interruption, callback failure, and terminal shutdown. Both commands exit with a failure if an assertion fails.

The example uses an injected clock and an in-memory transport; it does not wait in real time or connect to a game. Its event log includes:

```text
player-1/Charge/cast-1: ChargeStarted (0)
player-1/Charge/cast-1: Charging (0.5)
player-1/Charge/cast-1: Released (1.5)
```

To lint, check formatting, and build an importable Roblox model:

```sh
selene src tests examples
stylua --check src tests examples
rojo build default.project.json -o AbilityLifecycle.rbxm
```

Insert the resulting model into your test place. It is a folder containing the `Runner` and `Types` ModuleScripts. Require `Runner` from your composition code and supply a clock and transport using the contracts in `Types`. The model has no automatic startup scripts. The example is a Lune program, not a drop-in LocalScript.

## What to look for

- **Explicit dependencies:** the caller supplies time and replication; tests control both.
- **Private ownership:** active executions stay in closure state, while the returned API and each context are frozen.
- **Identity scoping:** executions are indexed by actor and use ID; replication carries the identifiers captured at `Begin`.
- **Terminal cleanup:** executions are removed before terminal callbacks, preventing recursive cancellation from finishing the same execution twice.
- **Recoverable errors:** callback failures become transition results, while `OnEnded` still receives a cleanup attempt.

## Integration boundaries

This is a trusted internal lifecycle component. A game's server must validate requests, derive actor identity, enforce ownership/cooldowns/rate limits, and validate outbound payloads in its adapters. The type declarations do not perform network validation.

Callbacks and the clock must be synchronous and non-yielding. `OnStart` and `OnHold` must not re-enter runner transitions. Terminal callbacks support the nested cancellation covered by the tests. Keep behavior definitions and injected dependencies stable during a use.

`Hold` is a one-time transition, not a per-frame update. Elapsed time is measured from `Begin`. Duplicate `Begin` and `Hold` calls are harmless while the execution is active; this is not a historical replay cache. Unknown `Cancel` succeeds without a change, while unknown `Hold` or `Release` returns a failure. `Destroy` is terminal, continues cleanup after callback failures, and does not return their errors.

See [the design notes](docs/systems/ability-lifecycle.md) for ownership, tradeoffs, and verification scope.

## Provenance and license

Copyright (c) 2026 Zachary Vanier. [MIT License](LICENSE).

[provenance.json](provenance.json) records the source snapshot and SHA-256 hashes of the unchanged extracted files. The example, standalone project configuration, and reading guide were added for this sample. No client project files, third-party effect packages, credentials, or original repository history are included.
