///|
struct LogSink {
  body : StringBuilder
}

///|
fn LogSink::new() -> LogSink {
  { body: StringBuilder::new() }
}

///|
pub impl @io.Writer for LogSink with write_once(self, buf, offset~, len~) {
  self.body.write_string(@utf8.decode(buf[offset:offset + len]))
  len
}

///|
struct TestResponseWriter {
  mut code : Int?
}

///|
suberror Boom derive(Debug)

///|
fn TestResponseWriter::new() -> TestResponseWriter {
  { code: None }
}

///|
pub impl @io.Writer for TestResponseWriter with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  ignore(self)
  ignore(buf)
  ignore(offset)
  len
}

///|
pub impl @moonback.ResponseWriter for TestResponseWriter with write_head(
  self,
  code,
  headers?,
) {
  ignore(headers)
  self.code = Some(code)
}

///|
pub impl @moonback.ResponseWriter for TestResponseWriter with flush(_self) {

}

///|
fn format_for_test(
  request_id : Int64,
  phase : String,
  meth_name : String,
  path : String,
  status : Int?,
  _started_at_ms : UInt64,
  _ended_at_ms : UInt64?,
  _duration_ms : Int64?,
  err : Error?,
) -> String {
  let status = match status {
    Some(status) => status.to_string()
    None => "-"
  }
  let err = match err {
    Some(_) => "err"
    None => "ok"
  }
  "\{request_id}|\{phase}|\{meth_name}|\{path}|\{status}|\{err}\n"
}

///|
async fn run_handler(
  handler : @moonback.Handler,
  meth : @http.RequestMethod,
  path : String,
) -> TestResponseWriter {
  let (body, sink) = @io.pipe()
  sink.close()
  defer body.close()
  let writer = TestResponseWriter::new()
  handler(
    { ctx: @moonback.mock_context, meth, path, headers: {}, body },
    writer,
  )
  writer
}

///|
async test "logging logs fast requests once" {
  let sink = LogSink::new()
  let handler = new(sink, format=format_for_test, slow_threshold_ms=100)(
    @moonback.Config::default(),
    (_r, w) => w.write_head(204),
  )
  let writer = run_handler(handler, Get, "/fast")
  assert_eq(writer.code, Some(204))
  inspect(
    sink.body.to_string(),
    content=(
      #|1|complete|GET|/fast|204|ok
      #|
    ),
  )
}

///|
async test "logging logs slow requests with start and end using same request id" {
  let sink = LogSink::new()
  let handler = new(sink, format=format_for_test, slow_threshold_ms=20)(
    @moonback.Config::default(),
    (_r, w) => {
      @async.sleep(40)
      w.write_head(200)
    },
  )
  let writer = run_handler(handler, Get, "/slow")
  assert_eq(writer.code, Some(200))
  inspect(
    sink.body.to_string(),
    content=(
      #|2|start|GET|/slow|-|ok
      #|2|end|GET|/slow|200|ok
      #|
    ),
  )
}

///|
async test "logging increments request id and logs errors" {
  let sink = LogSink::new()
  let handler = new(sink, format=format_for_test, slow_threshold_ms=100)(
    @moonback.Config::default(),
    (_r, w) => {
      w.write_head(500)
      raise Boom
    },
  )
  let writer = TestResponseWriter::new()
  let (body, sink_body) = @io.pipe()
  sink_body.close()
  defer body.close()
  let result = try? handler(
    { ctx: @moonback.mock_context, meth: Get, path: "/err", headers: {}, body },
    writer,
  )
  assert_true(result is Err(_))
  assert_eq(writer.code, Some(500))
  inspect(
    sink.body.to_string(),
    content=(
      #|3|complete|GET|/err|500|err
      #|
    ),
  )
}
