///|
extenum @moonback.TypedBox += {
  RequestId(String)
}

///|
let key : @moonback.TypedKey[String] = @moonback.TypedKey(
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
  @moonback.Middleware(next => {
    (req, res) => {
      let request_id = if req.app().config().trust_proxy &&
        header is Some(header) &&
        req.headers.get(header) is Some(id) {
        id.to_owned()
      } else {
        generator()
      }
      req.ctx.set_userdata(key, request_id)
      next(
        req,
        match header {
          None => res
          Some(header) =>
            (status, headers) => {
              let headers = headers.to_mut()..set(header, request_id).to_immut()
              res(status, headers)
            }
        },
      )
    }
  })
}

///|
pub fn get(req : @moonback.Request) -> String? {
  req.ctx.get_userdata(key)
}
