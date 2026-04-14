///|
pub struct UserdataKey[T] {
  val : Int
  box : (T) -> Error
  unbox : (Error) -> T?

  fn[T] new(box~ : (T) -> Error, unbox~ : (Error) -> T?) -> UserdataKey[T]
}

///|
struct Context {
  config : Config
  peer_addr : @socket.Addr
  mut userdata : @immut/sorted_map.SortedMap[Int, Error]
}

///|
let _userdata_next : Ref[Int] = { val: 0 }

///|
pub fn[T] UserdataKey::new(
  box~ : (T) -> Error,
  unbox~ : (Error) -> T?,
) -> UserdataKey[T] {
  let val = _userdata_next.val
  _userdata_next.val += 1
  { val, box, unbox }
}

///|
fn Context::mock() -> Context {
  {
    config: Config::default(),
    peer_addr: @socket.Addr::new(0, 0),
    userdata: @immut/sorted_map.SortedMap::new(),
  }
}

///|
pub fn[T] Context::get_userdata(self : Context, key : UserdataKey[T]) -> T? {
  match self.userdata.get(key.val) {
    None => None
    Some(val) => (key.unbox)(val)
  }
}

///|
pub fn[T] Context::set_userdata(
  self : Context,
  key : UserdataKey[T],
  val : T,
) -> Unit {
  self.userdata = self.userdata.add(key.val, (key.box)(val))
}
