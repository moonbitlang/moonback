///|
pub fn new(logger : &@io.BinaryWriter) -> @moonback.Middleware {
  Middleware(next => {
    (req, res) => {
      let start = @env.now()
      let mut status = 0
      next(req, (code, headers) => {
        status = code
        res.respond(status=code, headers~)
      })
      let elapsed = @env.now() - start
      logger.write(
        @utf8.encode(
          "[\{start}] \{req.meth.to_string()} \{req.path} -> \{status} (\{elapsed}ms)\n",
        ),
      )
    }
  })
}
