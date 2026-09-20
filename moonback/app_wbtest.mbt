///|
suberror IdleKeepAliveHandledTimeout

///|
suberror IdleKeepAliveCancelTimeout

///|
suberror BodyDisconnectCancelTimeout

///|
suberror BodyResponseTimeout

///|
suberror CloseBeforeResponseTimeout

///|
suberror CloseCancellationTimeout

///|
suberror UnusableReuseTimeout

///|
suberror HandlerFailure

///|
extend TrackedServerConnection with @io.Writer::{write_once}

///|
struct NoopWriteFlusher {}

///|
impl @io.Writer for NoopWriteFlusher with fn write_once(
  _self,
  _buf,
  offset~,
  len~,
) {
  let _ = offset
  len
}

///|
impl Flusher for NoopWriteFlusher with fn flush(_self) -> Unit {
  ()
}

///|
impl WriteFlusher for NoopWriteFlusher

///|
async fn run_with_fake_responder(app : App) -> Array[Int] {
  let statuses = []
  let writer = NoopWriteFlusher::{ }
  @async.with_task_group(group => {
    let req : Request = {
      ctx: Context::new(app, Mock),
      meth: Get,
      path: "/",
      search: None,
      headers: Headers::default(),
      params: {},
      body: { group, state: Unbuffered, },
    }
    app.handle_request(
      req,
      Responder((status, _headers) => {
        statuses.push(status)
        writer
      }),
    )
  })
  statuses
}

///|
async fn with_tracked_server_connection(
  f : async (TrackedServerConnection) -> Unit,
) -> Unit {
  let server = listen(port=0)
  defer server.close()
  @async.with_task_group(group => {
    let accept_task = group.spawn(() => server.accept())
    let client = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer client.close()
    let (conn, _) = accept_task.wait()
    defer conn.close()
    f(TrackedServerConnection::new(conn))
  })
}

///|
async test "tracked connection notifies close handlers on client disconnect" {
  with_tracked_server_connection(conn => {
    let mut closed = false
    let _unsubscribe = conn.on_close(() => closed = true)
    conn.notify_client_disconnected()
    assert_true(conn.is_client_disconnected())
    assert_true(conn.is_unusable())
    assert_true(closed)
  })
}

///|
async test "handle request sends 500 when handler fails before response" {
  let app = App(
    Module(ctx => ctx.get("/", (_req, _res) => raise HandlerFailure)),
  )
  defer app.close()
  @test.assert_eq(run_with_fake_responder(app), [500])
}

///|
async test "handle request does not send 500 after response started" {
  let app = App(
    Module(ctx => {
      ctx.get("/", (_req, res) => {
        res.send_void(status=204)
        raise HandlerFailure
      })
    }),
  )
  defer app.close()
  @test.assert_eq(run_with_fake_responder(app), [204])
}

///|
async test "handler reader error is not treated as tracked disconnect" {
  let app = App(
    Module(ctx => ctx.get("/", (_req, _res) => raise @io.ReaderClosed)),
  )
  defer app.close()
  with_tracked_server_connection(conn => {
    conn.notify_client_disconnected()
    @async.with_task_group(group => {
      let raw_req : @http.Request = { meth: Get, path: "/", headers: {}, }
      let req : Request = {
        ctx: Context::new(
          app,
          Normal(raw_req, conn, @socket.Addr::parse("127.0.0.1:0")),
        ),
        meth: Get,
        path: "/",
        search: None,
        headers: Headers::default(),
        params: {},
        body: { group, state: Unbuffered, },
      }
      let writer = NoopWriteFlusher::{ }
      try
        app.handle_request(req, Responder((_status, _headers) => writer))
      catch {
        @io.ReaderClosed => ()
        err => raise err
      } noraise {
        _ => fail("expected ReaderClosed")
      }
    })
  })
}

///|
async test "tracked connection does not treat long response body as client disconnect" {
  with_tracked_server_connection(conn => {
    let mut closed = false
    let _unsubscribe = conn.on_close(() => closed = true)
    conn.send_response(200, "OK", extra_headers={ "Content-Length": "1" })
    try conn.write_once(b"too long", offset=0, len=8) catch {
      @http.IncorrectBodyLength => ()
      err => raise err
    } noraise {
      _ => fail("expected IncorrectBodyLength")
    }
    assert_true(conn.is_unusable())
    assert_true(!conn.is_client_disconnected())
    assert_true(!closed)
  })
}

///|
async test "tracked connection does not treat short response body as client disconnect" {
  with_tracked_server_connection(conn => {
    let mut closed = false
    let _unsubscribe = conn.on_close(() => closed = true)
    conn.send_response(200, "OK", extra_headers={ "Content-Length": "2" })
    conn.write_once(b"x", offset=0, len=1) |> ignore
    try conn.end_response() catch {
      @http.IncorrectBodyLength => ()
      err => raise err
    } noraise {
      _ => fail("expected IncorrectBodyLength")
    }
    assert_true(conn.is_unusable())
    assert_true(!conn.is_client_disconnected())
    assert_true(!closed)
  })
}

///|
async test "serve stops reusing connection after handler makes connection unusable" {
  let mut second_handled = false
  let app = App(
    Module(ctx => {
      ctx.get("/bad", (_req, res) => {
        let writer = res.respond(status=200, headers={ "Content-Length": "1" })
        try writer.write("too long") catch {
          @http.IncorrectBodyLength => ()
          err => raise err
        } noraise {
          _ => fail("expected IncorrectBodyLength")
        }
      })
      ctx.get("/second", (_req, res) => {
        second_handled = true
        res.send_text("second")
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer conn.close()
    conn.write(
      "GET /bad HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nConnection: keep-alive\r\n\r\n",
    )
    conn.write(
      "GET /second HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nConnection: close\r\n\r\n",
    )
    @async.with_timeout(
      1000,
      () => ignore(conn.read_all()),
      error=UnusableReuseTimeout,
    ) catch {
      @io.ReaderClosed | @os_error.OSError(_) => ()
      err => raise err
    }
    assert_true(!second_handled)
    serve_task.cancel()
    serve_task.wait() catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}

///|
async test "serve_on_connection propagates response state errors" {
  let app = App(
    Module(ctx => {
      ctx.get("/bad", (_req, res) => {
        let writer = res.respond(status=200, headers={ "Content-Length": "1" })
        writer.write("too long")
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    defer server.close()
    let accept_task = group.spawn(() => server.accept())
    let client = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer client.close()
    let (conn, peer_addr) = accept_task.wait()
    let no_protect = @async.CondVar::Cond()
    let task = group.spawn(allow_failure=true, () => {
      app.serve_on_connection(conn, peer_addr, no_protect~)
    })
    client.write(
      "GET /bad HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nConnection: close\r\n\r\n",
    )
    try task.wait() catch {
      @http.IncorrectBodyLength => ()
      err => raise err
    } noraise {
      _ => fail("expected IncorrectBodyLength")
    }
  })
}

///|
async test "serve cancels idle keep-alive connections" {
  let mut handled = false
  let app = App(
    Module(ctx => {
      ctx.get("/", (_req, res) => {
        handled = true
        res.send_text("ok")
      })
    }),
    config=Config(stop_timeout=0.05),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer conn.close()
    conn.write(
      "GET / HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nConnection: keep-alive\r\n\r\n",
    )
    @async.with_timeout(
      500,
      () => {
        while !handled {
          @async.sleep(10)
        }
      },
      error=IdleKeepAliveHandledTimeout,
    )
    serve_task.cancel()
    @async.with_timeout(
      500,
      () => serve_task.wait(),
      error=IdleKeepAliveCancelTimeout,
    ) catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}

///|
#skip("unskip this test when async's bug fixed")
async test "serve cancels handler when content-length body is truncated" {
  let mut cancelled = false
  let app = App(
    Module(ctx => {
      ctx.post("/upload", (req, _res) => {
        defer {
          cancelled = @async.is_being_cancelled()
        }
        ignore(req.body.text() catch { _ => "" })
        @async.sleep(5000)
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    conn.write(
      "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nContent-Length: 12\r\n\r\nhello",
    )
    conn.close()
    @async.with_timeout(
      1000,
      () => {
        while !cancelled {
          @async.sleep(10)
        }
      },
      error=BodyDisconnectCancelTimeout,
    )
    serve_task.cancel()
    serve_task.wait() catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}

///|
async test "serve skips end_response after connection closes before response starts" {
  let mut handled = false
  let app = App(
    Module(ctx => {
      ctx.post("/upload", (req, _res) => {
        defer {
          handled = true
        }
        ignore(req.body.text() catch { _ => "" })
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    conn.write(
      "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello",
    )
    conn.close()
    @async.with_timeout(
      1000,
      () => {
        while !handled {
          @async.sleep(10)
        }
      },
      error=CloseBeforeResponseTimeout,
    )
    serve_task.cancel()
    serve_task.wait() catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}

///|
async test "serve cancels handler when chunked request body disconnects" {
  let mut cancelled = false
  let app = App(
    Module(ctx => {
      ctx.post("/upload", (req, _res) => {
        defer {
          cancelled = @async.is_being_cancelled()
        }
        ignore(req.body.text() catch { _ => "" })
        @async.sleep(5000)
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    conn.write(
      "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello",
    )
    conn.close()
    @async.with_timeout(
      1000,
      () => {
        while !cancelled {
          @async.sleep(10)
        }
      },
      error=CloseCancellationTimeout,
    )
    serve_task.cancel()
    serve_task.wait() catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}

///|
async test "serve does not treat complete body eof as disconnect" {
  let app = App(
    Module(ctx => {
      ctx.post("/upload", (req, res) => {
        let body = req.body.text()
        res.send_text(body)
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer conn.close()
    conn.write(
      "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello",
    )
    let header = @async.with_timeout(
      1000,
      () => conn.read_until("\r\n\r\n"),
      error=BodyResponseTimeout,
    )
    guard header is Some(header) else { fail("expected response header") }
    assert_true(header.contains("200 OK"))
    guard @async.with_timeout(
        1000,
        () => conn.read_until("hello"),
        error=BodyResponseTimeout,
      )
      is Some(_) else {
      fail("expected response body")
    }
    serve_task.cancel()
    serve_task.wait() catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}

///|
async test "serve does not treat empty request body as disconnect" {
  let app = App(
    Module(ctx => {
      ctx.get("/empty", (req, res) => {
        let body = req.body.text()
        res.send_text("empty=\{body.length()}")
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let serve_task = group.spawn(() => app.serve(server))
    let conn = @socket.Tcp::connect_to_host(
      "127.0.0.1",
      port=server.addr.port(),
    )
    defer conn.close()
    conn.write(
      "GET /empty HTTP/1.1\r\nHost: 127.0.0.1:\{server.addr.port()}\r\nConnection: close\r\n\r\n",
    )
    let header = @async.with_timeout(
      1000,
      () => conn.read_until("\r\n\r\n"),
      error=BodyResponseTimeout,
    )
    guard header is Some(header) else { fail("expected response header") }
    assert_true(header.contains("200 OK"))
    guard @async.with_timeout(
        1000,
        () => conn.read_until("empty=0"),
        error=BodyResponseTimeout,
      )
      is Some(_) else {
      fail("expected response body")
    }
    serve_task.cancel()
    serve_task.wait() catch {
      @async.TaskCancelled => ()
      err => raise err
    }
  })
}
