///|
async fn main {
  let api = @moonback.App(ctx => {
    ctx.get("/post/:id", (req, res) => {
      let id = req.params["id"]
      res.send_json({ "post_id": id })
    })
    ctx.get("/fail", (_req, _res) => {
      fail("This is an intentional error for testing")
    })
  })
  let app = @moonback.App(ctx => {
    ctx.add_middleware(@unstable_logreq.new(@stdio.stderr))
    ctx.add_middleware(
      @unstable_static.new(
        root="examples/serve_static_with_api/public",
        history_fallback=Some("/index.html"),
      ),
    )
    ctx.mount("/api", api)
  })

  println("Serving http://127.0.0.1:3000")
  println("Static files: /, /assets/app.css")
  println("SPA fallback: /dashboard/settings")
  println("API route: /api/post/:id")
  println("API route which fails: /api/fail")
  app.serve(@moonback.listen(host="127.0.0.1", port=3000))
}
