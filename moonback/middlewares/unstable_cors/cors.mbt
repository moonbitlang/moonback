///|
fn apply_preflight_headers(
  headers : @moonback.Headers,
  origin : String,
  methods : String,
  allow_headers : String,
  credentials : Bool,
  max_age : Int,
) -> Unit {
  headers.set("Access-Control-Allow-Origin", origin)
  headers.set("Access-Control-Allow-Methods", methods)
  headers.set("Access-Control-Allow-Headers", allow_headers)
  headers.set("Access-Control-Max-Age", max_age.to_string())
  if credentials {
    headers.set("Access-Control-Allow-Credentials", "true")
  }
}

///|
fn apply_response_headers(
  headers : @moonback.Headers,
  origin : String,
  methods : String,
  allow_headers : String,
  expose_headers : String,
  credentials : Bool,
) -> Unit {
  headers.set("Access-Control-Allow-Origin", origin)
  headers.set("Access-Control-Allow-Methods", methods)
  headers.set("Access-Control-Allow-Headers", allow_headers)
  headers.set("Access-Control-Expose-Headers", expose_headers)
  if credentials {
    headers.set("Access-Control-Allow-Credentials", "true")
  }
}

///|
fn is_preflight(req : @moonback.Request) -> Bool {
  req.meth is Options &&
  req.headers.get("origin") != None &&
  req.headers.get("access-control-request-method") != None
}

///|
fn cors_responder(
  inner : @moonback.Responder,
  origin : String,
  methods : String,
  allow_headers : String,
  expose_headers : String,
  credentials : Bool,
) -> @moonback.Responder {
  (status, headers) => {
    apply_response_headers(
      headers, origin, methods, allow_headers, expose_headers, credentials,
    )
    inner.respond(status~, headers~)
  }
}

///|
pub fn new(
  origin? : String = "*",
  methods? : String = "*",
  allow_headers? : String = "*",
  expose_headers? : String = "*",
  credentials? : Bool = false,
  max_age? : Int = 86400,
) -> @moonback.Middleware {
  @moonback.Middleware(next => {
    (req, res) => {
      if is_preflight(req) {
        let headers = @moonback.Headers::new()
        apply_preflight_headers(
          headers, origin, methods, allow_headers, credentials, max_age,
        )
        res.send_void(status=200, headers~)
      } else {
        next(
          req,
          cors_responder(
            res, origin, methods, allow_headers, expose_headers, credentials,
          ),
        )
      }
    }
  })
}
