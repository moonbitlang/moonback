///|
async fn http_get_text(port : Int, path : String) -> (Int, String) {
  let (response, body) = @http.get("http://127.0.0.1:\{port}\{path}")
  (response.code, body.text())
}

///|
suberror MountedHandlerFailure

///|
async test "mounted app receives slash-prefixed paths" {
  let child = App(
    Module(ctx => {
      ctx.get("/", (req, res) => res.send_text("root:\{req.path}"))
      ctx.get("/app.css", (req, res) => res.send_text("asset:\{req.path}"))
      ctx.get("/nested/file.txt", (req, res) => {
        res.send_text("nested:\{req.path}")
      })
    }),
  )
  let app = App(Module(ctx => ctx.mount("/assets", child)))
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    let port = server.addr.port()
    @test.assert_eq(http_get_text(port, "/assets"), (200, "root:/"))
    @test.assert_eq(http_get_text(port, "/assets/"), (200, "root:/"))
    @test.assert_eq(
      http_get_text(port, "/assets/app.css"),
      (200, "asset:/app.css"),
    )
    @test.assert_eq(
      http_get_text(port, "/assets/nested/file.txt"),
      (200, "nested:/nested/file.txt"),
    )
  })
}

///|
async test "root mounted app receives original absolute paths" {
  let child = App(
    Module(ctx => {
      ctx.get("/", (req, res) => res.send_text("root:\{req.path}"))
      ctx.get("/repo", (req, res) => res.send_text("repo:\{req.path}"))
    }),
  )
  let app = App(Module(ctx => ctx.mount("/", child)))
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    let port = server.addr.port()
    @test.assert_eq(http_get_text(port, "/"), (200, "root:/"))
    @test.assert_eq(http_get_text(port, "/repo"), (200, "repo:/repo"))
  })
}

///|
async test "static mount takes priority over root mount" {
  let assets = App(
    Module(ctx => {
      ctx.get("/app.css", (req, res) => res.send_text("asset:\{req.path}"))
    }),
  )
  let site = App(
    Module(ctx => {
      ctx.get("/assets/app.css", (req, res) => res.send_text("site:\{req.path}"))
    }),
  )
  let app = App(
    Module(ctx => {
      ctx.mount("/assets", assets)
      ctx.mount("/", site)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    let port = server.addr.port()
    @test.assert_eq(
      http_get_text(port, "/assets/app.css"),
      (200, "asset:/app.css"),
    )
  })
}

///|
async test "mounted app errors propagate to parent middleware by default" {
  let child = App(
    Module(ctx => ctx.get("/fail", (_req, _res) => raise MountedHandlerFailure)),
  )
  let app = App(
    Module(ctx => {
      ctx.add_middleware(
        Middleware(next => {
          (req, res) => {
            next(req, res) catch {
              MountedHandlerFailure =>
                res.send_text("caught by parent", status=502)
              err => raise err
            }
          }
        }),
      )
      ctx.mount("/api", child)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    @test.assert_eq(
      http_get_text(server.addr.port(), "/api/fail"),
      (502, "caught by parent"),
    )
  })
}

///|
async test "mounted app middleware can handle errors before propagation" {
  let child = App(
    Module(ctx => {
      ctx.add_middleware(
        Middleware(next => {
          (req, res) => {
            next(req, res) catch {
              MountedHandlerFailure =>
                res.send_text("caught by child", status=409)
              err => raise err
            }
          }
        }),
      )
      ctx.get("/fail", (_req, _res) => raise MountedHandlerFailure)
    }),
  )
  let app = App(
    Module(ctx => {
      ctx.add_middleware(
        Middleware(next => {
          (req, res) => {
            next(req, res) catch {
              MountedHandlerFailure =>
                res.send_text("caught by parent", status=502)
              err => raise err
            }
          }
        }),
      )
      ctx.mount("/api", child)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    @test.assert_eq(
      http_get_text(server.addr.port(), "/api/fail"),
      (409, "caught by child"),
    )
  })
}

///|
async test "mounted app can isolate errors from parent middleware" {
  let child = App(
    Module(ctx => ctx.get("/fail", (_req, _res) => raise MountedHandlerFailure)),
  )
  let app = App(
    Module(ctx => {
      ctx.add_middleware(
        Middleware(next => {
          (req, res) => {
            next(req, res) catch {
              MountedHandlerFailure =>
                res.send_text("caught by parent", status=502)
              err => raise err
            }
          }
        }),
      )
      ctx.mount("/api", child, error_mode=Isolate)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    @test.assert_eq(http_get_text(server.addr.port(), "/api/fail"), (500, ""))
  })
}

///|
async test "propagated error does not replace a committed response" {
  let child = App(
    Module(ctx => {
      ctx.get("/fail", (_req, res) => {
        res.send_text("started", status=202)
        raise MountedHandlerFailure
      })
    }),
  )
  let app = App(Module(ctx => ctx.mount("/api", child)))
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    @test.assert_eq(
      http_get_text(server.addr.port(), "/api/fail"),
      (202, "started"),
    )
  })
}
