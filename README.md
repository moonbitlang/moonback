# MoonBack

[![CI](https://github.com/moonbitlang/moonback/actions/workflows/ci.yml/badge.svg)](https://github.com/moonbitlang/moonback/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

MoonBack is an asynchronous web backend framework for
[MoonBit](https://www.moonbitlang.com/). It provides routing, middleware,
typed request and response helpers, WebSocket upgrades, graceful shutdown,
and module-scoped dependency injection.

MoonBack is a pre-1.0 project. The core APIs are usable, but compatibility may
change between minor releases. Packages under `middlewares/unstable_*` are
explicitly experimental.

## Install

Add MoonBack to your `moon.mod`:

```moonbit
import {
  "moonbitlang/async@0.21.0",
  "moonbitlang/moonback@0.8.2",
}

preferred_target = "native"
```

## Migrating from `hackwaly/moonback`

Starting with version 0.8.2, MoonBack is published as
`moonbitlang/moonback`. Replace the old dependency in `moon.mod`:

```moonbit
import {
  "moonbitlang/moonback@0.8.2",
}
```

Application source code can continue to use the `@moonback` package alias.
If you import an experimental middleware directly, update its full package
path from `hackwaly/moonback/middlewares/...` to
`moonbitlang/moonback/middlewares/...` as well.

## Quick start

```moonbit
async fn main {
  let app = @moonback.App(ctx => {
    ctx.get("/", (_req, res) => res.send_text("Hello, MoonBack!"))
  })
  defer app.close()

  let server = @moonback.listen(port=3000)
  app.serve(server)
}
```

See the [full guide](moonback/README.md) for routing, requests, responses,
WebSockets, middleware, dependency injection, configuration, and lifecycle
management.

## Repository layout

- `moonback/` contains the published `moonbitlang/moonback` module.
- `examples/` contains runnable examples for dependency injection, graceful
  shutdown, static files, and WebSockets.

## Contributing and security

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
opening a pull request. Please report security vulnerabilities according to
[SECURITY.md](SECURITY.md), not through a public issue.

## License

Licensed under the [Apache License 2.0](LICENSE).
