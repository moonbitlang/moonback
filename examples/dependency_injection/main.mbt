///|
struct Greeter {
  prefix : String
}

///|
priv suberror Dependencies {
  GreeterDependency(Greeter)
}

///|
let greeter_key : @moonback.TypedKey[Greeter] = @moonback.TypedKey(
  name="greeter",
  box=greeter => GreeterDependency(greeter),
  unbox=err => {
    match err {
      GreeterDependency(greeter) => Some(greeter)
      _ => None
    }
  },
)

///|
fn greeter_module() -> @moonback.Module {
  @moonback.Module(ctx => {
    let greeter = ctx.require(greeter_key)
    ctx.get("/", (_req, res) => {
      res.send_text("\{greeter.prefix}, MoonBack dependency injection!")
    })
  })
}

///|
fn root_module() -> @moonback.Module {
  @moonback.Module(ctx => {
    ctx.provide(greeter_key, { prefix: "Hello" })
    ctx.use_(greeter_module())
  })
}

///|
async fn main {
  let app = @moonback.App(root_module())
  defer app.close()
  let server = @moonback.listen(port=3000)
  println("Server listening on \{server.addr}")
  println("GET http://127.0.0.1:3000/")
  app.serve(server)
}
