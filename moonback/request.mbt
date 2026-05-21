///|
let _request_cookie_key : UserdataKey[Map[String, String]] = UserdataKey(
  box=cookies => Cookies(cookies),
  unbox=err => {
    match err {
      Cookies(cookies) => Some(cookies)
      _ => None
    }
  },
)

///|
/// Represents an incoming HTTP request handled by the application.
pub(all) struct Request {
  /// The request context, which holds per-request state and configuration.
  ctx : Context
  /// The HTTP method of the request (e.g. GET, POST).
  meth : @http.RequestMethod
  /// The request path, excluding the query string.
  path : StringView
  /// The raw query string, if any. This is the part after `?` in the URL.
  search : StringView?
  /// The request headers. This is an immutable view of the headers, and should be used for reading header values.
  headers : Headers
  /// The parsed path parameters for this request, if any. This is populated by the router when a route is matched.
  params : Map[StringView, StringView]
  /// The request body, which can be read as a stream or buffered in memory.
  body : RequestBody
}

///|
/// Returns the app instance handling this request. This can be used to access app-level configuration and state.
pub fn Request::app(self : Request) -> App {
  self.ctx.app
}

///|
/// Returns the client IP chain for this request.
/// When `trust_proxy` is enabled, this prefers `X-Forwarded-For`.
pub fn Request::ips(self : Request) -> ReadOnlyArray[StringView] {
  if self.ctx.app.config().trust_proxy &&
    self.headers.get_list("X-Forwarded-For") is x &&
    !x.is_empty() {
    x
  } else {
    match self.ctx.conn_info {
      Mock => []
      Normal(_, _, peer_addr) | Upgraded(_, peer_addr) =>
        [extract_host(peer_addr.to_string())]
    }
  }
}

///|
/// Returns the first client IP address for this request, if one is available.
pub fn Request::ip(self : Request) -> StringView? {
  self.ips().get(0)
}

///|
/// Returns the cookies sent with this request as a map of cookie name to value.
/// Cookies are parsed on demand and cached in the request context.
pub fn Request::cookie(self : Request) -> Map[String, String] {
  match self.ctx.get_userdata(_request_cookie_key) {
    Some(cookies) => cookies
    None => {
      let cookies = match self.headers.get("Cookie") {
        Some(raw) => parse_cookie(raw)
        None => {}
      }
      self.ctx.set_userdata(_request_cookie_key, cookies)
      cookies
    }
  }
}
