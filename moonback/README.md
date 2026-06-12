# MoonBack

MoonBack is an async web backend framework for MoonBit.

It provides a small routing layer, composable application modules, middleware,
typed request helpers, response helpers, graceful shutdown hooks, and
module-scoped dependency injection.

## Features

- Async HTTP server integration through `moonbitlang/async`
- Module-based app composition with `Module` and `ModuleContext`
- Route registration for `GET`, `POST`, and arbitrary HTTP methods
- Middleware chaining
- Typed query parameter and cookie helpers
- Response helpers for text, type-safe HTML, JSON, empty responses, and WebSocket upgrade
- App lifecycle cleanup with `ctx.on_close`
- Module-only dependency injection using `TypedKey`
- Typed custom application configuration values
- Optional app mounting for composing independent apps

## Installation

Add MoonBack to your `moon.mod`:

```moonbit
import {
  "moonbitlang/async@0.19.2",
  "hackwaly/moonback@0.6.4",
}
```

MoonBack is intended for the native target:

```moonbit
preferred_target = "native"
```

## Quick start

```moonbit
async fn main {
  let app = @moonback.App(ctx => {
    ctx.get("/", (_req, res) => {
      res.send_text("Hello, MoonBack!")
    })
  })
  defer app.close()

  let server = @moonback.listen(port=3000)
  println("Server listening on \{server.addr}")
  app.serve(server)
}
```

Run it with:

```bash
moon run .
```

Then open:

```text
http://127.0.0.1:3000/
```

## Modules

A `Module` is a reusable unit of application initialization. Modules register
routes, middleware, mounted apps, close hooks, and dependencies.

```moonbit
let posts_module : @moonback.Module = @moonback.Module(ctx => {
  ctx.get("/posts", list_posts)
  ctx.get("/posts/:id", show_post)
})

let admin_module : @moonback.Module = @moonback.Module(ctx => {
  ctx.add_middleware(require_admin)
  ctx.get("/admin/users", list_users)
})

async fn main {
  let app = @moonback.App(ctx => {
    ctx.use_(posts_module)
    ctx.use_(admin_module)
  })
  defer app.close()

  let server = @moonback.listen(port=3000)
  app.serve(server)
}
```

`ctx.use_` initializes the child module immediately in the same app context.

## Routing

MoonBack supports static paths, named parameters, and catch-all routes.

```moonbit
ctx.get("/", (_req, res) => {
  res.send_text("home")
})

ctx.get("/posts/:id", (req, res) => {
  let id = req.params["id"]
  res.send_text("post \{id}")
})

ctx.add_route(@http.Put, "/posts/:id", update_post)
```

When using `add_route` from your own package, import
`moonbitlang/async/http` and refer to methods as `@http.Get`, `@http.Put`,
and so on.

Supported helpers:

```moonbit
ctx.get(path, handler)
ctx.post(path, handler)
ctx.add_route(method, path, handler)
```

## Requests

Handlers receive a `Request` and a `Responder`.

```moonbit
ctx.get("/search", (req, res) => {
  let q = match req.query().get("q") {
    Some(q) => q
    None => ""
  }
  let cookies = req.cookie()
  let has_session = match cookies.get("session") {
    Some(_) => true
    None => false
  }
  let ip = match req.ip() {
    Some(ip) => ip.to_string()
    None => ""
  }

  res.send_json({
    "query": q,
    "has_session": has_session,
    "ip": ip,
  })
})
```

Useful request APIs:

- `req.meth`
- `req.path`
- `req.search`
- `req.headers`
- `req.params`
- `req.body.text()`
- `req.body.binary()`
- `req.body.json()`
- `req.query()`
- `req.cookie()`
- `req.ip()`
- `req.ips()`

MoonBack cancels the in-flight handler when it observes that the client
connection has been closed. This lets long-running handlers stop promptly and
release server-side resources instead of continuing work for a client that can
no longer receive the response.

Disconnects are observed through request or response I/O, such as an I/O error
while reading the request body or writing the response. If a handler does not
read the request body and does not write a response, there may be no I/O
operation that can discover the disconnect. Long-running or expensive handlers
should consume `req.body` when they need MoonBack to notice clients that close
the connection before the declared body has been fully sent.

## Responses

Use `Responder` helpers for common response types:

```moonbit
res.send_text("ok")
res.send_html(@moonback.Html::raw("<h1>Hello</h1>"))
res.send_json({ "ok": true })
res.send_void(status=204)
```

`send_html` accepts `Html` instead of a plain `String`, so escaped content and
trusted raw markup are explicit:

```moonbit
let page = @moonback.Html(builder => {
  let title = "Hello, <MoonBack>"
  builder <+ "<h1>\{title}</h1>"
})

res.send_html(page)
```

Use `Html::escape` for dynamic text and `Html(raw=...)` only for markup you
already trust.

For streaming responses, use `respond`:

```moonbit
ctx.get("/stream", (_req, res) => {
  let w = res.respond(status=200, headers={ "Content-Type": "text/plain" })
  w.write("first line\n")
  w.flush()
  w.write("second line\n")
})
```

## WebSocket

Use `Responder::upgrade` to upgrade an HTTP request to a WebSocket connection.
After the upgrade succeeds, do not send an HTTP response from the handler; use
the returned `@websocket.Conn` for bidirectional communication.

Add the WebSocket package to your `moon.pkg` when you need to handle messages:

```moonbit
import {
  "moonbitlang/async/websocket",
  "hackwaly/moonback",
}
```

Register a WebSocket route like any other route:

```moonbit
async fn serve_websocket(
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let ws = res.upgrade(req)
  defer ws.close()

  try {
    for ;; {
      let msg = ws.recv()
      match msg.kind {
        Text => {
          let text = msg.read_all().text()
          ws.send_text("echo: \{text}")
        }
        Binary => {
          let data = msg.read_all().binary()
          ws.send_binary(data)
        }
      }
    }
  } catch {
    @websocket.ConnectionClosed(_, _) => ()
    err => raise err
  }
}

let app = @moonback.App(ctx => {
  ctx.get("/ws", serve_websocket)
})
```

The returned WebSocket connection is valid only during request handling. Do not
store it after the handler finishes.

## Middleware

A middleware wraps the next handler.

```moonbit
let log_requests = @moonback.Middleware(next => {
  (req, res) => {
    println("\{req.meth} \{req.path}")
    next(req, res)
  }
})

let app = @moonback.App(ctx => {
  ctx.add_middleware(log_requests)
  ctx.get("/", (_req, res) => res.send_text("ok"))
})
```

Middleware is applied in registration order.

## Dependency injection

MoonBack dependency injection is intentionally available only during module
initialization through `ModuleContext`. Handlers should capture dependencies
from module initialization instead of resolving them from `App` or `Request`.

Define a typed key:

```moonbit
struct Greeter {
  prefix : String
}

extenum @moonback.TypedBox += {
  GreeterDependency(Greeter)
}

let greeter_key : @moonback.TypedKey[Greeter] = @moonback.TypedKey(
  name="greeter",
  box=greeter => GreeterDependency(greeter),
  unbox=err => {
    match err {
      GreeterDependency(greeter) => Some(greeter)
      _ => None
    }
  },
)
```

Provide and require it from modules:

```moonbit
let greeter_module : @moonback.Module = @moonback.Module(ctx => {
  let greeter = ctx.require(greeter_key)

  ctx.get("/", (_req, res) => {
    res.send_text("\{greeter.prefix}, MoonBack!")
  })
})

let app = @moonback.App(ctx => {
  ctx.provide(greeter_key, { prefix: "Hello" })
  ctx.use_(greeter_module)
})
```

Available APIs:

```moonbit
ctx.provide(key, value)
ctx.resolve(key)
ctx.require(key)
```

`provide` fails on duplicate dependencies. `require` fails when a dependency is
missing. `resolve` returns `None` when a dependency is missing.

See `../examples/dependency_injection` for a complete runnable example.

## Request userdata

`TypedKey` can also be used for request-scoped userdata, which is useful for
middleware that computes values for later handlers.

```moonbit
req.ctx.set_userdata(key, value)
req.ctx.get_userdata(key)
```

Dependency injection and request userdata use the same key type, but different
stores and lifetimes:

- dependencies are app-scoped and module-initialization only
- userdata is request-scoped

## App configuration

```moonbit
let app = @moonback.App(
  root_module(),
  config=@moonback.Config(
    trust_proxy=true,
    max_connections=1024,
    stop_timeout=5.0,
  ),
)
```

Config fields:

- `trust_proxy`: use proxy headers such as `X-Forwarded-For`
- `max_connections`: limit concurrent accepted connections
- `stop_timeout`: graceful shutdown timeout in seconds

You can also attach typed custom values to app configuration. Custom config
uses the same `TypedKey` pattern as dependency injection and request userdata,
but values are stored on `Config` and are available through `app.config()`.

```moonbit
extenum @moonback.TypedBox += {
  UploadRoot(String)
}

let upload_root_key : @moonback.TypedKey[String] = @moonback.TypedKey(
  name="upload_root",
  box=root => UploadRoot(root),
  unbox=boxed => {
    match boxed {
      UploadRoot(root) => Some(root)
      _ => None
    }
  },
)

let app = @moonback.App(
  root_module(),
  config=@moonback.Config(
    custom=[
      @moonback.Config::custom(upload_root_key, "/srv/uploads"),
    ],
  ),
)

let upload_root = app.config().get_custom(upload_root_key)
```

## Cleanup hooks

Register cleanup callbacks with `ctx.on_close`:

```moonbit
let app = @moonback.App(ctx => {
  let db = connect_db()
  ctx.on_close(() => db.close())
})

defer app.close()
```

Close hooks run in reverse registration order.

## Mounting apps

Mount another app under a path:

```moonbit
let api = @moonback.App(ctx => {
  ctx.get("/health", (_req, res) => res.send_text("ok"))
})

let app = @moonback.App(ctx => {
  ctx.mount("/api", api)
})
```

Mounted apps are independent apps. By default, the parent app owns and closes
the mounted app.

## Development

Useful commands:

```bash
moon check
moon test
moon fmt
moon info
```

`moon info` updates `pkg.generated.mbti`, which records the public API surface.

## License

Apache-2.0
