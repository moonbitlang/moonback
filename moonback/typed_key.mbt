///|
pub extenum TypedBox {}

///|
/// A typed key used to store and retrieve custom values from typed stores.
struct TypedKey[T] {
  val : Int
  name : String
  box : (T) -> TypedBox
  unbox : (TypedBox) -> T?
}

///|
let _typed_key_next : Ref[Int] = { val: 0 }

///|
/// Creates a fresh typed key with custom boxing and unboxing logic.
pub fn[T] TypedKey::TypedKey(
  name? : String = "unnamed",
  box~ : (T) -> TypedBox,
  unbox~ : (TypedBox) -> T?,
) -> TypedKey[T] {
  let val = _typed_key_next.val
  _typed_key_next.val += 1
  { val, name, box, unbox }
}

///|
/// Returns the debug name associated with this key.
pub fn[T] TypedKey::name(self : TypedKey[T]) -> String {
  self.name
}
