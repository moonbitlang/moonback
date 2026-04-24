///|
/// A mutable HTTP header collection with special handling for `Set-Cookie`.
pub struct Headers {
  priv headers : Map[String, String]
  priv mut set_cookie : Array[StringView]

  fn new() -> Headers
}

///|
struct ImmutableHeaders(Headers)

///|
/// Converts a value into `Headers`.
pub trait ToHeaders {
  to_headers(Self) -> Headers
}

///|
/// Creates an empty header collection.
pub fn Headers::new() -> Headers {
  { headers: {}, set_cookie: [] }
}

///|
/// Returns an empty header collection.
pub impl Default for Headers with default() {
  Headers()
}

///|
/// Converts any `ToHeaders` value into `Headers`.
pub fn Headers::from(from : &ToHeaders) -> Headers {
  from.to_headers()
}

///|
fn Headers::from_request(headers : Map[String, String]) -> Headers {
  { headers, set_cookie: [] }
}

///|
/// Returns a header value by name.
/// Multiple values are joined with `, `.
pub fn Headers::get(self : Headers, name : String) -> StringView? {
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
/// Returns all values for a header name.
/// For regular headers, comma-separated values are split into a list.
pub fn Headers::get_list(self : Headers, name : String) -> Array[StringView] {
  let name = name.to_lower()
  if name == "set-cookie" {
    return self.set_cookie
  }
  match self.headers.get(name) {
    None => []
    Some(value) => value.split(",").map(s => s.trim()).to_array()
  }
}

///|
/// Sets a header value, replacing any existing values.
pub fn Headers::set(self : Headers, name : String, value : String) -> Unit {
  let name = name.to_lower()
  if name == "set-cookie" {
    self.set_cookie = [value]
    return
  }
  self.headers[name.to_lower()] = value
}

///|
/// Adds a header value to the existing values for `name`.
pub fn Headers::add(self : Headers, name : String, value : String) -> Unit {
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
/// Adds a `Set-Cookie` header value.
pub fn Headers::add_set_cookie(self : Headers, cookie : @http.Cookie) -> Unit {
  self.set_cookie.push(cookie_to_header_value(cookie))
}

///|
/// Removes all values for the given header name.
pub fn Headers::remove(self : Headers, name : String) -> Unit {
  let name = name.to_lower()
  if name == "set-cookie" {
    self.set_cookie = []
    return
  }
  self.headers.remove(name)
}

///|
/// Iterates over all headers as lowercase name-value pairs.
pub fn Headers::iter(self : Headers) -> Iter[(String, String)] {
  Iter::concat(
    self.headers.iter(),
    self.set_cookie.iter().map(cookie => ("set-cookie", cookie.to_string())),
  )
}

///|
/// Returns a header value by name.
pub fn ImmutableHeaders::get(
  self : ImmutableHeaders,
  name : String,
) -> StringView? {
  self.0.get(name)
}

///|
/// Returns all values for a header name.
pub fn ImmutableHeaders::get_list(
  self : ImmutableHeaders,
  name : String,
) -> Array[StringView] {
  self.0.get_list(name)
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
  { headers, set_cookie }
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
  { headers, set_cookie }
}

///|
pub impl ToHeaders for ImmutableHeaders with to_headers(self) -> Headers {
  { headers: self.0.headers.copy(), set_cookie: self.0.set_cookie.copy() }
}

///|
/// Iterates over all headers as lowercase name-value pairs.
pub fn ImmutableHeaders::iter(
  self : ImmutableHeaders,
) -> Iter[(String, String)] {
  self.0.iter()
}
