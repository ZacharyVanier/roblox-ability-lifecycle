# Roblox Ability Lifecycle

A Luau ability lifecycle runner by **Zachary Vanier**, from VZN Framework.

Handles start, hold, release, cancellation, and cleanup. The caller supplies the clock and network transport. No runtime package dependencies.

## Start here

1. [ChargeAbility.luau](examples/ChargeAbility.luau) — runnable example.
2. [Types.luau](src/VZNCore/Features/Behavior/Shared/Types.luau) — public API.
3. [Runner.luau](src/VZNCore/Features/Behavior/Shared/Runner.luau) — implementation.
4. [Runner.spec.luau](tests/Features/Behavior/Runner.spec.luau) — tests.

## Run it

With Rokit installed, run from the repository root:

```sh
rokit install
lune run tests/Features/Behavior/Runner.spec.luau
lune run examples/ChargeAbility.luau
```

The five tests cover lifecycle ordering, duplicate input, replication identity, and nested cleanup. The example also checks interruption, callback failure, and shutdown using a simulated clock and local event log.

To lint, check formatting, and build an importable Roblox model:

```sh
selene src tests examples
stylua --check src tests examples
rojo build default.project.json -o AbilityLifecycle.rbxm
```

Insert the model into your test place, require its `Runner` ModuleScript, and supply a clock and transport as defined in `Types`. The model contains only the two modules; your game owns startup. The example runs in Lune.

## Integration boundaries

This is a trusted internal lifecycle component. A game's server must validate requests, derive actor identity, enforce ownership/cooldowns/rate limits, and validate outbound payloads in its adapters. The type declarations do not perform network validation.

Callbacks and the clock must be synchronous and non-yielding. `OnStart` and `OnHold` must not re-enter runner transitions. Terminal callbacks support the nested cancellation covered by the tests. Keep behavior definitions and injected dependencies stable during a use.

`Hold` is a one-time transition, not a per-frame update. Elapsed time is measured from `Begin`. Duplicate `Begin` and `Hold` calls are harmless while the execution is active; this is not a historical replay cache. Unknown `Cancel` succeeds without a change, while unknown `Hold` or `Release` returns a failure. `Destroy` is terminal, continues cleanup after callback failures, and does not return their errors.

See [the design notes](docs/systems/ability-lifecycle.md) for cleanup ownership and failure semantics.

## Provenance and license

Copyright (c) 2026 Zachary Vanier. [MIT License](LICENSE).

The runtime modules and original tests are unchanged from VZN Framework. [provenance.json](provenance.json) records their source commit and hashes.
