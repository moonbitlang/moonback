///|
async fn main {
  let app = @moonback.App(ctx => {
    ctx.use_(@logreq.new(@stdio.stderr))
    ctx.use_(
      @unstable_static.new(
        "examples/serve_static/public",
        history_fallback=true,
      ),
    )
    ctx.get("/api/ping", (_req, w) => {
      w.write_head(200, headers={ "Content-Type": "application/json" })
      w.write(
        (
          #|{ "message": "pong" }
          #|
        ),
      )
    })
  })

  println("Serving http://127.0.0.1:3000")
  println("Static files: /, /assets/app.css")
  println("SPA fallback: /dashboard/settings")
  println("API route: /api/ping")
  app.serve(@moonback.listen(host="127.0.0.1", port=3000))
}
