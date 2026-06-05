///|
extenum TypedBox += {
  StringDependency(String)
  IntDependency(Int)
}

///|
let _string_dependency_key : TypedKey[String] = TypedKey(
  name="string_dependency",
  box=value => StringDependency(value),
  unbox=err => {
    match err {
      StringDependency(value) => Some(value)
      _ => None
    }
  },
)

///|
let _unnamed_int_dependency_key : TypedKey[Int] = TypedKey(
  box=value => IntDependency(value),
  unbox=err => {
    match err {
      IntDependency(value) => Some(value)
      _ => None
    }
  },
)

///|
async test "module context provides and resolves dependencies" {
  let mut resolved_in_module = ""
  let app = App(
    Module(ctx => {
      ctx.provide(_string_dependency_key, "provided")
      @test.assert_eq(ctx.resolve(_string_dependency_key), Some("provided"))
      resolved_in_module = ctx.require(_string_dependency_key)
    }),
  )
  defer app.close()
  @test.assert_eq(resolved_in_module, "provided")
}

///|
async test "composed modules share dependencies" {
  let mut resolved_in_child = ""
  let child = Module(ctx => {
    resolved_in_child = ctx.require(_string_dependency_key)
  })
  let app = App(
    Module(ctx => {
      ctx.provide(_string_dependency_key, "shared")
      ctx.use_(child)
    }),
  )
  defer app.close()
  @test.assert_eq(resolved_in_child, "shared")
}

///|
async test "handlers use dependencies captured during module initialization" {
  let mut resolved_in_handler = ""
  let app = App(
    Module(ctx => {
      ctx.provide(_string_dependency_key, "handler")
      let dependency = ctx.require(_string_dependency_key)
      ctx.get("/", (_req, res) => {
        resolved_in_handler = dependency
        res.send_void(status=204)
      })
    }),
  )
  defer app.close()
  @async.with_task_group(group => {
    let server = listen(port=0)
    let task = group.spawn(() => app.serve(server))
    let port = server.addr.port()
    let (response, _) = @http.get("http://127.0.0.1:\{port}/")
    task.cancel()
    @test.assert_eq(response.code, 204)
  })
  @test.assert_eq(resolved_in_handler, "handler")
}

///|
async test "duplicate dependency raises with key name" {
  try {
    let app = App(
      Module(ctx => {
        ctx.provide(_string_dependency_key, "one")
        ctx.provide(_string_dependency_key, "two")
      }),
    )
    app.close()
    fail("expected duplicate dependency")
  } catch {
    DuplicateDependency(name~) => @test.assert_eq(name, "string_dependency")
    err => raise err
  }
}

///|
async test "missing dependency raises with default key name" {
  try {
    let app = App(
      Module(ctx => {
        let _ = ctx.require(_unnamed_int_dependency_key)
      }),
    )
    app.close()
    fail("expected missing dependency")
  } catch {
    MissingDependency(name~) => @test.assert_eq(name, "unnamed")
    err => raise err
  }
}
