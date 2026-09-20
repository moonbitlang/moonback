///|
async fn expect_task_cancelled(task : @async.Task[Unit]) -> Unit {
  try @async.with_timeout(1000, () => task.wait()) catch {
    @async.TaskCancelled => ()
    err => raise err
  } noraise {
    _ => fail("expected task cancellation")
  }
}

///|
async test "request cancellation bypasses error handlers and runs cleanup" {
  let started = @async.Semaphore(1, initial_value=0)
  let blocked = @async.CondVar::Cond()
  let statuses : Array[Int] = []
  let mut cleaned_up = false
  let mut error_cleanup = false
  let mut caught = false
  let mut returned = false
  let app = App(ctx => {
    ctx.add_middleware(
      Middleware(next => {
        (req, res) => {
          next(req, res) catch {
            _ => {
              caught = true
              res.send_void(status=500)
            }
          }
        }
      }),
    )
    ctx.get("/", (_req, _res) => {
      defer @async.protect_from_cancel(() => {
        @async.sleep(1)
        cleaned_up = true
      })
      errdefer {
        error_cleanup = true
      }
      started.release()
      blocked.wait()
    })
  })
  defer app.close()
  @async.with_task_group(group => {
    let task = group.spawn(() => {
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
          NoopWriteFlusher::{ }
        }),
      )
      returned = true
    })
    @async.with_timeout(1000, () => started.acquire())
    task.cancel()
    expect_task_cancelled(task)
  })
  @test.assert_eq(statuses, [])
  assert_true(cleaned_up)
  assert_true(error_cleanup)
  assert_false(caught)
  assert_false(returned)
}

///|
async test "waiting for a cancelled child is an ordinary handler error" {
  let app = App(ctx => {
    ctx.get("/", (_req, _res) => {
      @async.with_task_group(group => {
        let task = group.spawn(() => @async.sleep(5000))
        task.cancel()
        task.wait()
      })
    })
  })
  defer app.close()
  @test.assert_eq(run_with_fake_responder(app), [500])
}

///|
async test "cancelled connection IO is unusable but not a client disconnect" {
  with_tracked_server_connection(conn => {
    let mut closed = false
    let _unsubscribe = conn.on_close(() => closed = true)
    let result = @async.with_timeout_opt(20, () => conn.read_request())
    assert_true(result is None)
    assert_true(conn.is_unusable())
    assert_false(conn.is_client_disconnected())
    assert_false(closed)
  })
}

///|
async test "serve lets in-flight requests finish during graceful shutdown" {
  let started = @async.Semaphore(1, initial_value=0)
  let finish = @async.Semaphore(1, initial_value=0)
  let mut cancelled = false
  let app = App(
    ctx => {
      ctx.get("/", (_req, res) => {
        defer {
          cancelled = @async.is_being_cancelled()
        }
        started.release()
        finish.acquire()
        res.send_text("finished")
      })
    },
    config=Config(stop_timeout=5),
  )
  defer app.close()
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let mut released = false
      defer (if !released { finish.release() })
      let server = listen(port=0)
      let serve_task = group.spawn(() => app.serve(server))
      let request = group.spawn(() => {
        let (response, body) = @http.get(
          "http://127.0.0.1:\{server.addr.port()}/",
        )
        (response.code, body.text())
      })
      started.acquire()
      serve_task.cancel()
      @async.sleep(20)
      assert_false(cancelled)
      finish.release()
      released = true
      @test.assert_eq(request.wait(), (200, "finished"))
      expect_task_cancelled(serve_task)
    })
  })
  assert_false(cancelled)
}

///|
async test "serve cancels unfinished requests at the shutdown deadline" {
  for max_connections in [None, Some(1)] {
    for stop_timeout in [0.0, 0.02] {
      let started = @async.Semaphore(1, initial_value=0)
      let mut cancelled = false
      let mut completed = false
      let app = App(
        ctx => {
          ctx.get("/", (_req, res) => {
            defer {
              cancelled = @async.is_being_cancelled()
            }
            started.release()
            @async.sleep(500)
            completed = true
            res.send_void(status=204)
          })
        },
        config=Config(max_connections?, stop_timeout~),
      )
      defer app.close()
      @async.with_task_group(group => {
        let server = listen(port=0)
        let serve_task = group.spawn(() => app.serve(server))
        let client = @socket.Tcp::connect_to_host(
          "127.0.0.1",
          port=server.addr.port(),
        )
        defer client.close()
        client.write("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        @async.with_timeout(1000, () => started.acquire())
        serve_task.cancel()
        expect_task_cancelled(serve_task)
      })
      assert_true(cancelled)
      assert_false(completed)
    }
  }
}

///|
struct ObservedListener {
  server : @http.Server
  accepting : @async.Semaphore
  accepted : @async.Semaphore
  mut closed : Bool
}

///|
impl Listener for ObservedListener with fn accept(self) {
  self.accepting.release()
  let connection = self.server.accept()
  self.accepted.release()
  connection
}

///|
impl Listener for ObservedListener with fn close(self) {
  self.closed = true
  self.server.close()
}

///|
async test "serve cancels promptly without connections and respects listener ownership" {
  for take_ownership in [true, false] {
    let app = App(_ctx => (), config=Config(stop_timeout=5))
    defer app.close()
    let listener : ObservedListener = {
      server: listen(port=0),
      accepting: @async.Semaphore(1, initial_value=0),
      accepted: @async.Semaphore(1, initial_value=0),
      closed: false,
    }
    defer listener.server.close()
    @async.with_task_group(group => {
      let task = group.spawn(() => app.serve(listener, take_ownership~))
      @async.with_timeout(1000, () => listener.accepting.acquire())
      task.cancel()
      expect_task_cancelled(task)
    })
    @test.assert_eq(listener.closed, take_ownership)
  }
}

///|
async test "serve closes accepted connections waiting for a connection slot" {
  let started = @async.Semaphore(1, initial_value=0)
  let app = App(
    ctx => {
      ctx.get("/", (_req, res) => {
        started.release()
        @async.sleep(500)
        res.send_void(status=204)
      })
    },
    config=Config(max_connections=1, stop_timeout=0),
  )
  defer app.close()
  let listener : ObservedListener = {
    server: listen(port=0),
    accepting: @async.Semaphore(2, initial_value=0),
    accepted: @async.Semaphore(2, initial_value=0),
    closed: false,
  }
  defer listener.server.close()
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let serve_task = group.spawn(() => app.serve(listener))
      let client = @socket.Tcp::connect_to_host(
        "127.0.0.1",
        port=listener.server.addr.port(),
      )
      defer client.close()
      client.write("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
      started.acquire()
      listener.accepted.acquire()
      let pending = @socket.Tcp::connect_to_host(
        "127.0.0.1",
        port=listener.server.addr.port(),
      )
      defer pending.close()
      listener.accepted.acquire()
      serve_task.cancel()
      expect_task_cancelled(serve_task)
      let body = pending.read_all().binary() catch {
          @io.ReaderClosed | @os_error.OSError(_) => b""
          err => raise err
        }
      @test.assert_eq(body, b"")
    })
  })
  assert_true(listener.closed)
}

///|
async test "serve cancels upgraded websocket handlers at the shutdown deadline" {
  let started = @async.Semaphore(1, initial_value=0)
  let mut cancelled = false
  let app = App(
    ctx => {
      ctx.get("/ws", (req, res) => {
        let websocket = res.upgrade(req)
        defer websocket.close()
        defer {
          cancelled = @async.is_being_cancelled()
        }
        started.release()
        ignore(@async.with_timeout(500, () => websocket.recv()))
      })
    },
    config=Config(stop_timeout=0.02),
  )
  defer app.close()
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let server = listen(port=0)
      let serve_task = group.spawn(() => app.serve(server))
      let websocket = @websocket.connect(
        "ws://127.0.0.1:\{server.addr.port()}/ws",
      )
      defer websocket.close()
      started.acquire()
      serve_task.cancel()
      expect_task_cancelled(serve_task)
    })
  })
  assert_true(cancelled)
}
