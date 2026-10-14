///|
async fn main {
  let app = @moonback.App(ctx => {
    ctx.on_close(() => println("Cleaning up resources..."))
    ctx.get(
      "/ws",
      @moonback.cancel_on_shutdown().apply((req, res) => {
        let ws = res.upgrade(req)
        for i in 1..<@int.MAX_VALUE {
          ws.send_text("\{i}")
          @async.sleep(1000)
        }
      }),
    )
    ctx.get("/", (_req, res) => {
      println("Handling request...")
      let w = res.respond(status=200, headers={ "Content-Type": "text/html" })
      w.write(
        (
          #|<html>
          #|<body>
          #|<script>
          #|  const ws = new WebSocket(`ws://${location.host}/ws`);
          #|  ws.onmessage = (event) => {
          #|    console.log(event.data);
          #|  };
          #|</script>
          #|<h1>Hello, world!</h1>
          #|<pre>
        ),
      )
      for i in 0..<20 {
        println("Writing data... \{i}")
        w.write("\{i}\n")
        w.flush()
        @async.sleep(250)
      }
      w.write(
        (
          #|</pre>
          #|</body>
          #|</html>
        ),
      )
      println("Done writing response.")
    })
  })
  defer app.close()
  let server = @moonback.listen(port=3000)
  println("Server listening on \{server.addr}")
  app.serve(server)
  println("Shutdown complete.")
}
