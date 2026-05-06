///|
fn method_name(meth : @http.RequestMethod) -> String {
  match meth {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
pub fn new(logger : &@io.Writer) -> @moonback.Middleware {
  @moonback.Middleware(next => {
    (req, res) => {
      let start = @env.now()
      let mut status = 0
      next(req, (code, headers) => {
        status = code
        res.respond(status=code, headers~)
      })
      let elapsed = @env.now() - start
      logger.write(
        "[\{start}] \{method_name(req.meth)} \{req.path} -> \{status} (\{elapsed}ms)\n",
      )
    }
  })
}
