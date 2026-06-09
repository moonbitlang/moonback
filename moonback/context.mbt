///|
struct Context {
  app : App
  mut conn_info : ConnectionInfo
  mut committed : Bool
  mut userdata : @immut/sorted_map.SortedMap[Int, TypedBox]
}

///|
#warnings("-unused_field")
priv enum ConnectionInfo {
  Mock
  Normal(@http.Request, @http.ServerConnection, @socket.Addr)
  Upgraded(@websocket.Conn, @socket.Addr)
}

///|
fn Context::new(app : App, conn_info : ConnectionInfo) -> Context {
  {
    app,
    committed: false,
    conn_info,
    userdata: @immut/sorted_map.SortedMap::new(),
  }
}

///|
/// Returns a typed userdata value previously stored under `key`.
pub fn[T] Context::get_userdata(self : Context, key : TypedKey[T]) -> T? {
  match self.userdata.get(key.val) {
    None => None
    Some(val) => (key.unbox)(val)
  }
}

///|
/// Stores a typed userdata value under `key`.
pub fn[T] Context::set_userdata(
  self : Context,
  key : TypedKey[T],
  val : T,
) -> Unit {
  self.userdata = self.userdata.add(key.val, (key.box)(val))
}

///|
/// Wraps a handler with middlewares. The middlewares will be applied in the order they are given.
/// Example:
/// ```moonbit nocheck
/// ctx.get(
///   "/",
///   ctx.with_middlewares([middleware1, middleware2]) <| ((req, res) => {
///     ...
///   })
/// )
/// ```
pub fn Context::with_middlewares(
  _self : Context,
  middlewares : ArrayView[Middleware],
  handler : Handler,
) -> Handler {
  Middleware::chain(middlewares)(handler)
}
