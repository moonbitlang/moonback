///|
let _headers_next_owner_id : Ref[Int] = { val: 0 }

///|
const HEADERS_SHARED_OWNER_ID : Int = -1

///|
/// A mutable HTTP header collection with special handling for `Set-Cookie`.
priv struct HeaderStore {
  mut owner_id : Int
  headers : Map[String, String]
  mut set_cookie : Array[StringView]
}

///|
fn HeaderStore::copy(self : HeaderStore, owner_id? : Int) -> HeaderStore {
  {
    owner_id: owner_id.unwrap_or(self.owner_id),
    headers: self.headers.copy(),
    set_cookie: self.set_cookie.copy(),
  }
}

///|
fn HeaderStore::iter(self : HeaderStore) -> Iter[(String, String)] {
  Iter::concat(
    self.headers.iter(),
    self.set_cookie.iter().map(cookie => ("set-cookie", cookie.to_owned())),
  )
}

///|
fn HeaderStore::get(self : HeaderStore, name : String) -> StringView? {
  let name = name.to_lower()
  if name == "set-cookie" {
    return match self.set_cookie {
      [] => None
      [cookie] => Some(cookie)
      cookies => Some(cookies.join(", "))
    }
  }
  match self.headers.get(name.to_lower()) {
    None => None
    Some(value) => Some(value)
  }
}

///|
fn HeaderStore::get_list(
  self : HeaderStore,
  name : String,
) -> ReadOnlyArray[StringView] {
  let name = name.to_lower()
  if name == "set-cookie" {
    return ReadOnlyArray::from_array(self.set_cookie)
  }
  match self.headers.get(name) {
    None => []
    Some(value) => ReadOnlyArray::from_iter(value.split(",").map(s => s.trim()))
  }
}

///|
fn HeaderStore::set(self : HeaderStore, name : String, value : String) -> Unit {
  let name = name.to_lower()
  if name == "set-cookie" {
    self.set_cookie = [value]
    return
  }
  self.headers[name.to_lower()] = value
}

///|
fn HeaderStore::add(self : HeaderStore, name : String, value : String) -> Unit {
  let name = name.to_lower()
  if name == "set-cookie" {
    self.set_cookie.push(value)
    return
  }
  match self.headers.get(name) {
    None => self.headers[name] = value
    Some(old) => self.headers[name] = old + ", " + value
  }
}

///|
fn HeaderStore::add_set_cookie(
  self : HeaderStore,
  cookie : @http.Cookie,
) -> Unit {
  self.set_cookie.push(cookie_to_header_value(cookie))
}

///|
fn HeaderStore::remove(self : HeaderStore, name : String) -> Unit {
  let name = name.to_lower()
  if name == "set-cookie" {
    self.set_cookie = []
    return
  }
  self.headers.remove(name)
}

///|
#valtype
struct Headers {
  store : HeaderStore
}

///|
let default_headers : Headers = {
  store: { owner_id: HEADERS_SHARED_OWNER_ID, headers: {}, set_cookie: [] },
}

///|
pub fn Headers::Headers() -> Headers {
  default_headers
}

///|
pub impl Default for Headers with default() -> Headers {
  default_headers
}

///|
/// Converts any `ToHeaders` value into `Headers`.
pub fn Headers::from(from : &ToHeaders) -> Headers {
  from.to_headers()
}

///|
fn Headers::from_request(headers : Map[String, String]) -> Headers {
  let store = { owner_id: HEADERS_SHARED_OWNER_ID, headers, set_cookie: [] }
  { store, }
}

///|
pub fn Headers::to_mut(self : Headers) -> MutHeaders {
  let owner_id = _headers_next_owner_id.val
  _headers_next_owner_id.val += 1
  { owner_id, store: self.store }
}

///|
/// Returns a header value by name.
/// Multiple values are joined with `, `.
pub fn Headers::get(self : Headers, name : String) -> StringView? {
  self.store.get(name)
}

///|
/// Returns all values for a header name.
/// For regular headers, comma-separated values are split into a list.
pub fn Headers::get_list(
  self : Headers,
  name : String,
) -> ReadOnlyArray[StringView] {
  self.store.get_list(name)
}

///|
/// Iterates over all headers as lowercase name-value pairs.
pub fn Headers::iter(self : Headers) -> Iter[(String, String)] {
  self.store.iter()
}

///|
pub trait ToHeaders {
  to_headers(Self) -> Headers
}

///|
struct MutHeaders {
  owner_id : Int
  mut store : HeaderStore
}

///|
pub fn MutHeaders::MutHeaders() -> MutHeaders {
  let owner_id = _headers_next_owner_id.val
  _headers_next_owner_id.val += 1
  { owner_id, store: { owner_id, headers: {}, set_cookie: [] } }
}

///|
pub fn MutHeaders::from(headers : &ToHeaders) -> MutHeaders {
  headers.to_headers().to_mut()
}

///|
fn MutHeaders::ensure_owned(self : MutHeaders) -> Unit {
  if self.owner_id != self.store.owner_id {
    self.store = self.store.copy(owner_id=self.owner_id)
  }
}

///|
/// Returns a header value by name.
/// Multiple values are joined with `, `.
pub fn MutHeaders::get(self : MutHeaders, name : String) -> StringView? {
  self.store.get(name)
}

///|
/// Returns all values for a header name.
/// For regular headers, comma-separated values are split into a list.
pub fn MutHeaders::get_list(
  self : MutHeaders,
  name : String,
) -> ReadOnlyArray[StringView] {
  self.store.get_list(name)
}

///|
/// Iterates over all headers as lowercase name-value pairs.
pub fn MutHeaders::iter(self : MutHeaders) -> Iter[(String, String)] {
  self.store.iter()
}

///|
/// Sets a header value, replacing any existing values.
pub fn MutHeaders::set(
  self : MutHeaders,
  name : String,
  value : String,
) -> Unit {
  self.ensure_owned()
  self.store.set(name, value)
}

///|
/// Adds a header value to the existing values for `name`.
pub fn MutHeaders::add(
  self : MutHeaders,
  name : String,
  value : String,
) -> Unit {
  self.ensure_owned()
  self.store.add(name, value)
}

///|
/// Adds a `Set-Cookie` header value.
pub fn MutHeaders::add_set_cookie(
  self : MutHeaders,
  cookie : @http.Cookie,
) -> Unit {
  self.ensure_owned()
  self.store.add_set_cookie(cookie)
}

///|
/// Removes all values for the given header name.
pub fn MutHeaders::remove(self : MutHeaders, name : String) -> Unit {
  self.ensure_owned()
  self.store.remove(name)
}

///|
pub fn MutHeaders::to_immut(self : MutHeaders) -> Headers {
  self.store.owner_id = HEADERS_SHARED_OWNER_ID
  { store: self.store }
}

///|
pub impl ToHeaders for MutHeaders with to_headers(self) -> Headers {
  self.to_immut()
}

///|
pub impl ToHeaders for Headers with to_headers(self) -> Headers {
  self
}

///|
pub impl ToHeaders for Map[String, String] with to_headers(self) -> Headers {
  let headers = {}
  let set_cookie = []
  for k, v in self {
    let k = k.to_lower()
    if k == "set-cookie" {
      set_cookie.push(v[:])
      continue
    }
    headers[k] = v
  }
  let store = { owner_id: HEADERS_SHARED_OWNER_ID, headers, set_cookie }
  { store, }
}

///|
pub impl ToHeaders for Array[(String, String)] with to_headers(self) -> Headers {
  let headers = {}
  let set_cookie = []
  for pair in self {
    let (k, v) = pair
    let k = k.to_lower()
    if k == "set-cookie" {
      set_cookie.push(v[:])
      continue
    }
    match headers.get(k) {
      None => headers[k] = v
      Some(old) => headers[k] = old + ", " + v
    }
  }
  let store = { owner_id: HEADERS_SHARED_OWNER_ID, headers, set_cookie }
  { store, }
}
