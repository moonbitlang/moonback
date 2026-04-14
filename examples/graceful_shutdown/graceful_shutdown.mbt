///|
async fn main {
  @async.with_task_group(group => {
    let app = @moonback.App(ctx => {
      ctx.get("/", (_r, w) => {
        println("Handling request...")
        w.write_head(200, headers={ "Content-Type": "text/html" })
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
    // TODO: Use signal handler once we have.
    group.spawn_bg(() => {
      @async.sleep(4000)
      println("Shutting down...")
      app.shutdown()
      println("Shutdown complete.")
    })
    app.serve(@moonback.listen(port=3000))
  })
}
