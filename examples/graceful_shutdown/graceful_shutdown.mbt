///|
async fn main {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      let app = @moonback.App(ctx => {
        ctx.on_close(() => println("Cleaning up resources..."))
        ctx.get("/", (_req, res) => {
          println("Handling request...")
          let w = res.respond(status=200, headers={
            "Content-Type": "text/html",
          })
          w.write("<html><body><h1>Hello, world!</h1><pre>")
          for i in 0..<20 {
            println("Writing data... \{i}")
            w.write("\{i}\n")
            w.flush()
            @async.sleep(250)
          }
          w.write("</pre></body></html>")
          println("Done writing response.")
        })
      })
      defer app.close()
      let server = @moonback.listen(port=3000)
      println("Server listening on \{server.addr}")
      app.serve(server)
    })
    // TODO: Use signal handler once we have.
    group.spawn_bg(() => {
      @async.sleep(4000)
      println("Shutting down...")
      task.cancel()
    })
  })
  println("Shutdown complete.")
}
