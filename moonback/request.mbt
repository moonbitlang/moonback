///|
pub(all) struct Request {
  ctx : Context
  meth : @http.RequestMethod
  path : String
  headers : Map[String, String]
  body : &@io.Reader
}

///|
pub fn Request::ips(self : Request) -> Array[StringView] {
  if self.ctx.config.trust_proxy &&
    self.headers.get("X-Forwarded-For") is Some(ips) {
    ips.split(",").to_array()
  } else {
    [extract_host(self.ctx.peer_addr.to_string())]
  }
}

///|
pub fn Request::ip(self : Request) -> StringView? {
  self.ips().get(0)
}
