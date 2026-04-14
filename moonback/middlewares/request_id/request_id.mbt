///|
priv suberror Key {
  RequestId(String)
}

///|
let key : @moonback.UserdataKey[String] = @moonback.UserdataKey(
  box=id => RequestId(id),
  unbox=err => {
    match err {
      RequestId(id) => Some(id)
      _ => None
    }
  },
)

///|
pub fn new(
  generator~ : () -> String,
  header? : String? = Some("X-Request-ID"),
) -> @moonback.Middleware {
  @moonback.Middleware((config, next) => {
    (req, w) => {
      let request_id = if config.trust_proxy &&
        header is Some(header) &&
        req.headers.get(header) is Some(id) {
        id
      } else {
        generator()
      }
      req.ctx.set_userdata(key, request_id)
      next(
        req,
        match header {
          Some(header) =>
            w.with_headers(headers => headers.set(header, request_id))
          None => w
        },
      )
    }
  })
}

///|
pub fn get(req : @moonback.Request) -> String? {
  req.ctx.get_userdata(key)
}
