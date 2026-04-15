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
      logger.write("\{method_name(req.meth)} \{req.path}")
      next(req, res)
    }
  })
}
