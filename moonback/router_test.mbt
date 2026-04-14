///|
struct TestWriter {
  mut code : Int?
}

///|
fn TestWriter::new() -> TestWriter {
  { code: None }
}

///|
pub impl @io.Writer for TestWriter with write_once(self, buf, offset~, len~) {
  ignore(self)
  ignore(buf)
  ignore(offset)
  len
}

///|
pub impl ResponseWriter for TestWriter with write_head(self, code, headers?) {
  ignore(headers)
  self.code = Some(code)
}

///|
pub impl ResponseWriter for TestWriter with flush(_self) {

}

///|
fn test_handler(code : Int) -> Handler {
  (_r, w) => w.write_head(code)
}

///|
async fn run_handler(handler : Handler) -> Int? {
  let (body, sink) = @io.pipe()
  sink.close()
  defer body.close()
  let writer = TestWriter::new()
  handler(
    { ctx: mock_context, meth: Get, path: "/", headers: {}, body },
    writer,
  )
  writer.code
}

///|
async test "router dispatches get and post handlers independently" {
  let router = Router::new()
  let get_handler = test_handler(201)
  let post_handler = test_handler(202)
  router.add_route(Get, "/users", get_handler)
  router.add_route(Post, "/users", post_handler)

  match router.route(Get, "/users") {
    Some({ handler, .. }) => assert_eq(run_handler(handler), Some(201))
    None => fail("expected get route")
  }
  match router.route(Post, "/users") {
    Some({ handler, .. }) => assert_eq(run_handler(handler), Some(202))
    None => fail("expected post route")
  }
}

///|
test "router rejects duplicate method registration on the same path" {
  let router = Router::new()
  router.add_route(Get, "/users", test_handler(201))
  let result = try? router.add_route(Get, "/users", test_handler(204))

  guard result is Err(RouteConflict(path="/users")) else {
    fail("expected RouteConflict")
  }
}

///|
test "router returns none when method is not registered" {
  let router = Router::new()
  router.add_route(Get, "/users", test_handler(200))

  match router.route(Post, "/users") {
    None => ()
    Some(_) => fail("expected no route")
  }
}

///|
async test "router uses fallback for unregistered methods on the same path" {
  let router = Router::new()
  router.add_route(Get, "/users", test_handler(200))
  router.add_fallback_route("/users", test_handler(299))

  match router.route(Patch, "/users") {
    Some({ handler, .. }) => assert_eq(run_handler(handler), Some(299))
    None => fail("expected fallback route")
  }
}

///|
test "router rejects duplicate fallback registration on the same path" {
  let router = Router::new()
  router.add_fallback_route("/users", test_handler(299))
  let result = try? router.add_fallback_route("/users", test_handler(300))

  guard result is Err(RouteConflict(path="/users")) else {
    fail("expected RouteConflict")
  }
}

///|
test "router keeps params when resolving handlers" {
  let router = Router::new()
  router.add_route(Get, "/users/:id", test_handler(200))

  match router.route(Get, "/users/42") {
    Some({ params, .. }) => assert_eq(params.get("id"), Some("42"))
    None => fail("expected route")
  }
}
