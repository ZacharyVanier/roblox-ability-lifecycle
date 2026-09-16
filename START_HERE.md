# Start here

Ability and skill lifecycle code from VZN Framework, my larger Roblox ECS framework. Its custom ECS engine is inspired by [jecs](https://github.com/Ukendio/jecs).

1. [Ability runner](src/Behavior/Shared/Runner.luau) — start, hold, release, cancellation, and cleanup.
2. [Skill service](src/Skills/Server/Service.luau) — validation, cooldowns, charges, and request handling. Shared definitions and lifecycle rules are in [Skills/Shared](src/Skills/Shared).
3. [Charge ability example](examples/ChargeAbility.luau) — a complete use of the runner.
4. [Tests](tests) — lifecycle, cooldowns, replay protection, request ordering, and cleanup.

Run the tests with `lune run tests/run-all.luau` and the example with `lune run examples/ChargeAbility.luau`.
