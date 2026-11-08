///|
suberror RouteTemplateFailure

///|
async test "route templates identify the selected registered handler" {
  let observed : Array[StringView?] = []
  let handler : Handler = (req, res) => {
    observed.push(req.route_template())
    res.send_void(status=if req.path == "/not-found" { 404 } else { 204 })
  }
  let app = App(
    Module(ctx => {
      ctx.add_middleware(next => {
        (req, res) => {
          observed.push(req.route_template())
          next(req, res)
          observed.push(req.route_template())
        }
      })
      ctx.get("/", handler)
      ctx.get("/health", handler)
      ctx.get("/users/:id", handler)
      ctx.post("/users/:name", handler)
      ctx.add_route(@http.Put, "/users/:key", handler)
      ctx.get("/files/*rest", handler)
      ctx.get("/not-found", handler)
    }),
  )
  defer app.close()
  let cases : Array[(@http.RequestMethod, StringView, StringView?, Int32)] = [
    (Get, "/", Some("/"), 204),
    (Get, "/health", Some("/health"), 204),
    (Get, "/users/42", Some("/users/:id"), 204),
    (Post, "/users/42", Some("/users/:name"), 204),
    (Put, "/users/42", Some("/users/:key"), 204),
    (Get, "/files/css/app.css", Some("/files/*rest"), 204),
    (Get, "/not-found", Some("/not-found"), 404),
    (Get, "/missing", None, 404),
    (Delete, "/users/42", None, 404),
  ]
  @async.with_task_group(group => {
    for (meth, path, template, status) in cases {
      let start = observed.length()
      let statuses : Array[Int32] = []
      let req : Request = {
        ctx: Context::new(app, Mock),
        meth,
        path,
        search: Some("expand=profile"),
        headers: Headers::default(),
        params: {},
        body: { group, state: Unbuffered, },
      }
      @test.assert_eq(req.route_template(), None)
      app.handle_request(
        req,
        Responder((status, _headers) => {
          statuses.push(status)
          NoopWriteFlusher::{ }
        }),
      )
      @test.assert_eq(statuses, [status])
      let expected = match template {
        Some(_) => [template, template, template]
        None => [None, None]
      }
      @test.assert_eq(observed[start:].to_owned(), expected)
      @test.assert_eq(req.route_template(), template)
    }
  })
}

///|
async test "nested dynamic mounts expose complete templates to middleware" {
  let observed : Array[(String, StringView?)] = []
  let child = App(
    Module(ctx => {
      ctx.add_middleware(next => {
        (req, res) => {
          observed.push(("child.before", req.route_template()))
          next(req, res)
          observed.push(("child.after", req.route_template()))
        }
      })
      let handler : Handler = (req, res) => {
        observed.push(("handler", req.route_template()))
        res.send_text(req.path.to_owned())
      }
      ctx.get("/", handler)
      ctx.get("/users/:id", handler)
      ctx.get("/files/*rest", handler)
    }),
  )
  let tenants = App(
    Module(ctx => {
      ctx.add_middleware(next => {
        (req, res) => {
          observed.push(("tenants.before", req.route_template()))
          next(req, res)
          observed.push(("tenants.after", req.route_template()))
        }
      })
      ctx.mount("/tenants/:tenant", child)
    }),
  )
  let app = App(
    Module(ctx => {
      ctx.add_middleware(next => {
        (req, res) => {
          observed.push(("parent.before", req.route_template()))
          next(req, res)
          observed.push(("parent.after", req.route_template()))
        }
      })
      ctx.mount("/api/", tenants)
    }),
  )
  defer app.close()
  let cases : Array[(String, String, StringView?)] = [
    (
      "/api/tenants/acme/users/42?expand=profile",
      "/users/42",
      Some("/api/tenants/:tenant/users/:id"),
    ),
    ("/api/tenants/acme", "/", Some("/api/tenants/:tenant/")),
    ("/api/tenants/acme/", "/", Some("/api/tenants/:tenant/")),
    (
      "/api/tenants/other/files/css/app.css",
      "/files/css/app.css",
      Some("/api/tenants/:tenant/files/*rest"),
    ),
    ("/api/tenants/acme/missing", "", None),
  ]
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    for (path, body, template) in cases {
      let start = observed.length()
      let status = if template is Some(_) { 200 } else { 404 }
      @test.assert_eq(http_get_text(server.addr.port(), path), (status, body))
      let expected = [
        ("parent.before", None),
        ("tenants.before", None),
        ("child.before", template),
      ]
      if template is Some(_) {
        expected.push(("handler", template))
      }
      expected.append([
        ("child.after", template),
        ("tenants.after", template),
        ("parent.after", template),
      ])
      @test.assert_eq(observed[start:].to_owned(), expected)
    }
  })
}

///|
async test "root mounts and concurrent requests keep their own templates" {
  let entered = @async.Semaphore(2, initial_value=0)
  let release = @async.Semaphore(2, initial_value=0)
  let child = App(
    Module(ctx => {
      ctx.get("/users/:id", (req, res) => {
        entered.release()
        release.acquire()
        guard req.route_template() is Some(template) else {
          fail("expected matched route template")
        }
        res.send_text(template.to_owned())
      })
    }),
  )
  let root = App(Module(ctx => ctx.mount("/", child)))
  let app = App(
    Module(ctx => {
      ctx.mount("/left", root)
      ctx.mount("/right", child, take_ownership=false)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    defer task.cancel()
    let left = group.spawn(() => {
      http_get_text(server.addr.port(), "/left/users/1")
    })
    let right = group.spawn(() => {
      http_get_text(server.addr.port(), "/right/users/2")
    })
    entered.acquire()
    entered.acquire()
    release.release()
    release.release()
    @test.assert_eq(left.wait(), (200, "/left/users/:id"))
    @test.assert_eq(right.wait(), (200, "/right/users/:id"))
  })
}

///|
async test "repeated mount forwarding restores the prefix after returning" {
  let observed : Array[StringView?] = []
  let child = App(
    Module(ctx => {
      ctx.get("/users/:id", (req, _res) => observed.push(req.route_template()))
    }),
  )
  let app = App(
    Module(ctx => {
      ctx.add_middleware(next => {
        (req, res) => {
          next(req, res)
          observed.push(req.route_template())
          next(req, res)
          observed.push(req.route_template())
          res.send_void(status=204)
        }
      })
      ctx.mount("/api", child)
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let req : Request = {
      ctx: Context::new(app, Mock),
      meth: Get,
      path: "/api/users/42",
      search: None,
      headers: Headers::default(),
      params: {},
      body: { group, state: Unbuffered, },
    }
    let statuses : Array[Int32] = []
    app.handle_request(
      req,
      Responder((status, _headers) => {
        statuses.push(status)
        NoopWriteFlusher::{ }
      }),
    )
    @test.assert_eq(statuses, [204])
    @test.assert_eq(observed, [
      Some("/api/users/:id"),
      Some("/api/users/:id"),
      Some("/api/users/:id"),
      Some("/api/users/:id"),
    ])
  })
}

///|
async test "propagated and isolated errors retain templates and restore prefixes" {
  for error_mode in [Propagate, Isolate] {
    let observed : Array[StringView?] = []
    let child = App(
      Module(ctx => {
        ctx.get("/fail", (req, _res) => {
          observed.push(req.route_template())
          raise RouteTemplateFailure
        })
      }),
    )
    let nested = App(Module(ctx => ctx.mount("/v1", child)))
    let app = App(
      Module(ctx => {
        ctx.add_middleware(next => {
          (req, res) => {
            @test.assert_eq(req.route_template(), None)
            next(req, res) catch {
              RouteTemplateFailure => res.send_void(status=502)
              err => raise err
            }
            observed.push(req.route_template())
          }
        })
        ctx.mount("/api", nested, error_mode~)
      }),
    )
    defer app.close()
    @async.with_task_group(group => {
      let req : Request = {
        ctx: Context::new(app, Mock),
        meth: Get,
        path: "/api/v1/fail",
        search: None,
        headers: Headers::default(),
        params: {},
        body: { group, state: Unbuffered, },
      }
      let statuses : Array[Int32] = []
      for _ in 0..<2 {
        app.handle_request(
          req,
          Responder((status, _headers) => {
            statuses.push(status)
            NoopWriteFlusher::{ }
          }),
        )
      }
      let status = match error_mode {
        Propagate => 502
        Isolate => 500
      }
      @test.assert_eq(statuses, [status, status])
      @test.assert_eq(observed, [
        Some("/api/v1/fail"),
        Some("/api/v1/fail"),
        Some("/api/v1/fail"),
        Some("/api/v1/fail"),
      ])
    })
  }
}

///|
async test "cancelled mount forwarding restores the prefix before redispatch" {
  let started = @async.Semaphore(1, initial_value=0)
  let child = App(
    Module(ctx => {
      ctx.get("/wait", (_req, _res) => {
        started.release()
        @async.sleep(60000)
      })
      ctx.get("/ready", (req, res) => {
        @test.assert_eq(req.route_template(), Some("/api/ready"))
        res.send_void(status=204)
      })
    }),
  )
  let app = App(Module(ctx => ctx.mount("/api", child)))
  defer app.close()
  @async.with_task_group(group => {
    let req : Request = {
      ctx: Context::new(app, Mock),
      meth: Get,
      path: "/api/wait",
      search: None,
      headers: Headers::default(),
      params: {},
      body: { group, state: Unbuffered, },
    }
    let statuses : Array[Int32] = []
    let res = Responder((status, _headers) => {
      statuses.push(status)
      NoopWriteFlusher::{ }
    })
    let task = group.spawn(() => app.handle_request(req, res))
    started.acquire()
    task.cancel()
    task.wait() catch {
      @async.WaitedTaskAlreadyCancelled => ()
      err => raise err
    }
    @test.assert_eq(req.route_template(), Some("/api/wait"))
    app.handle_request({ ..req, path: "/api/ready", }, res)
    @test.assert_eq(statuses, [204])
    app.handle_request({ ..req, path: "/missing", }, res)
    @test.assert_eq(req.route_template(), None)
    @test.assert_eq(statuses, [204, 404])
  })
}
