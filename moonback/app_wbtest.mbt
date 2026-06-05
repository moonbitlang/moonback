///|
suberror IdleKeepAliveHandledTimeout

///|
suberror IdleKeepAliveCancelTimeout

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
      err if @async.is_cancellation_error(err) => ()
      err => raise err
    }
  })
}
