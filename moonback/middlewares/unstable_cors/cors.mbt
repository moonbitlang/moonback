///|
fn vary_contains(vary : String, value : String) -> Bool {
  let value = value.to_lower()
  for part in vary.split(",") {
    if part.trim().to_string().to_lower() == value {
      return true
    }
  }
  false
}

///|
fn append_vary(headers : @moonback.Headers, value : String) -> Unit {
  match headers.get("Vary") {
    Some(existing) =>
      if !vary_contains(existing, value) {
        headers.set("Vary", "\{existing}, \{value}")
      }
    None => headers.set("Vary", value)
  }
}

///|
fn resolve_allow_origin(
  origin : String,
  allow_origin : String,
  allow_credentials : Bool,
) -> (String, Bool) {
  if allow_origin == "*" && allow_credentials {
    (origin, true)
  } else {
    (allow_origin, false)
  }
}

///|
fn set_headers(
  headers : @moonback.Headers,
  origin : String,
  allow_origin : String,
  allow_credentials : Bool,
  expose_headers : String?,
) -> Unit {
  let (resolved_origin, vary_origin) = resolve_allow_origin(
    origin, allow_origin, allow_credentials,
  )
  headers.set("Access-Control-Allow-Origin", resolved_origin)
  if allow_credentials {
    headers.set("Access-Control-Allow-Credentials", "true")
  }
  if expose_headers is Some(expose_headers) {
    headers.set("Access-Control-Expose-Headers", expose_headers)
  }
  if vary_origin {
    append_vary(headers, "Origin")
  }
}

///|
fn preflight_headers(
  origin : String,
  allow_origin : String,
  allow_methods : Array[String],
  allow_headers : String?,
  allow_credentials : Bool,
  max_age : Int?,
  request_headers : String?,
) -> Map[String, String] {
  let headers = @moonback.Headers()
  set_headers(headers, origin, allow_origin, allow_credentials, None)
  headers.set("Access-Control-Allow-Methods", allow_methods.join(", "))
  match allow_headers {
    Some(allow_headers) =>
      headers.set("Access-Control-Allow-Headers", allow_headers)
    None =>
      if request_headers is Some(request_headers) {
        headers.set("Access-Control-Allow-Headers", request_headers)
        append_vary(headers, "Access-Control-Request-Headers")
      }
  }
  if max_age is Some(max_age) {
    headers.set("Access-Control-Max-Age", max_age.to_string())
  }
  headers.repr()
}

///|
/// Cross-Origin Resource Sharing middleware.
///
/// The middleware adds CORS response headers for requests with an `Origin`
/// header. For preflight `OPTIONS` requests carrying
/// `Access-Control-Request-Method`, it responds with `204` directly.
pub fn new(
  allow_origin? : String = "*",
  allow_methods? : Array[String] = [
    "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS",
  ],
  allow_headers? : String? = None,
  expose_headers? : String? = None,
  allow_credentials? : Bool = false,
  max_age? : Int? = None,
) -> @moonback.Middleware {
  @moonback.Middleware((_config, next) => {
    (req, w) => {
      let origin = match req.headers.get("Origin") {
        Some(origin) => origin
        None => {
          next(req, w)
          return
        }
      }

      if req.meth is Options &&
        req.headers.get("Access-Control-Request-Method") is Some(_) {
        w.write_head(
          204,
          headers=preflight_headers(
            origin,
            allow_origin,
            allow_methods,
            allow_headers,
            allow_credentials,
            max_age,
            req.headers.get("Access-Control-Request-Headers"),
          ),
        )
        return
      }

      next(
        req,
        w.with_headers(headers => {
          set_headers(
            headers, origin, allow_origin, allow_credentials, expose_headers,
          )
        }),
      )
    }
  })
}
