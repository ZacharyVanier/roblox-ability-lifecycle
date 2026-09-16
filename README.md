# Ability and skill lifecycle

This is a code sample from VZN Framework, my larger Roblox ECS framework. Its ECS engine is inspired by [jecs](https://github.com/Ukendio/jecs).

Start with [Runner.luau](src/Behavior/Shared/Runner.luau) for ability execution and cleanup. [Service.luau](src/Skills/Server/Service.luau) adds skill validation, cooldowns, and charges.

[ChargeAbility.luau](examples/ChargeAbility.luau) shows how to use the runner. The [tests](tests) cover lifecycle, request handling, and cleanup.

With Lune installed, run `lune run tests/run-all.luau` for the tests or `lune run examples/ChargeAbility.luau` for the example.
