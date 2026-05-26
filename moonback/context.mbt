///|
/// A typed key used to store and retrieve custom values from a context.
pub struct UserdataKey[T] {
  val : Int
  box : (T) -> Error
  unbox : (Error) -> T?
}

///|
struct Context {
  app : App
  mut conn_info : ConnectionInfo
  mut userdata : @immut/sorted_map.SortedMap[Int, Error]
}

///|
#warnings("-unused_field")
priv enum ConnectionInfo {
  Mock
  Normal(@http.Request, @http.ServerConnection, @socket.Addr)
  Upgraded(@websocket.Conn, @socket.Addr)
}

///|
let _userdata_next : Ref[Int] = { val: 0 }

///|
/// Creates a fresh userdata key with custom boxing and unboxing logic.
pub fn[T] UserdataKey::UserdataKey(
  box~ : (T) -> Error,
  unbox~ : (Error) -> T?,
) -> UserdataKey[T] {
  let val = _userdata_next.val
  _userdata_next.val += 1
  { val, box, unbox }
}

///|
fn Context::new(app : App, conn_info : ConnectionInfo) -> Context {
  { app, conn_info, userdata: @immut/sorted_map.SortedMap::new() }
}

///|
/// Returns a typed userdata value previously stored under `key`.
pub fn[T] Context::get_userdata(self : Context, key : UserdataKey[T]) -> T? {
  match self.userdata.get(key.val) {
    None => None
    Some(val) => (key.unbox)(val)
  }
}

///|
/// Stores a typed userdata value under `key`.
pub fn[T] Context::set_userdata(
  self : Context,
  key : UserdataKey[T],
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
