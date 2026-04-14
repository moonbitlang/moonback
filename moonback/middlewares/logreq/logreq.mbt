///|
let request_id_counter : Ref[Int64] = Ref::new(0L)

///|
fn next_request_id() -> Int64 {
  request_id_counter.val = request_id_counter.val + 1
  request_id_counter.val
}

///|
fn method_name(meth : @http.RequestMethod) -> String {
  @debug.to_string(meth).to_upper()
}

///|
fn status_name(status : Int?) -> String {
  match status {
    Some(status) => status.to_string()
    None => "pending"
  }
}

///|
fn error_suffix(err : Error?) -> String {
  match err {
    Some(err) => " error=\{@debug.to_string(err)}"
    None => ""
  }
}

///|
fn pad2(n : Int) -> String {
  n.to_string().pad_start(2, '0')
}

///|
fn civil_from_days(days_since_epoch : Int64) -> (Int, Int, Int) {
  let z = days_since_epoch + 719468L
  let era = z / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = (doy - (153L * mp + 2L) / 5L + 1L).to_int()
  let month_offset = if mp < 10L { 3L } else { -9L }
  let month = (mp + month_offset).to_int()
  let year_offset = if month <= 2 { 1L } else { 0L }
  let year = (y + year_offset).to_int()
  (year, month, day)
}

///|
fn format_timestamp(ts_ms : UInt64) -> String {
  let seconds = (ts_ms / 1000UL).reinterpret_as_int64()
  let days = seconds / 86_400
  let seconds_of_day = (seconds % 86_400).to_int()
  let hour = seconds_of_day / 3600
  let minute = seconds_of_day % 3600 / 60
  let second = seconds_of_day % 60
  let (year, month, day) = civil_from_days(days)
  "\{year}/\{pad2(month)}/\{pad2(day)} \{pad2(hour)}:\{pad2(minute)}:\{pad2(second)}"
}

///|
pub fn default_format(
  request_id : Int64,
  phase : String,
  meth_name : String,
  path : String,
  status : Int?,
  started_at_ms : UInt64,
  ended_at_ms : UInt64?,
  duration_ms : Int64?,
  err : Error?,
) -> String {
  match phase {
    "start" =>
      "[\{format_timestamp(started_at_ms)}] [req:\{request_id}] START \{meth_name} \{path} status=\{status_name(status)}\n"
    "end" =>
      "[\{format_timestamp(ended_at_ms.unwrap())}] [req:\{request_id}] END   \{meth_name} \{path} -> \{status_name(status)} (\{duration_ms.unwrap()}ms)\{error_suffix(err)}\n"
    _ =>
      "[\{format_timestamp(ended_at_ms.unwrap())}] [req:\{request_id}] \{meth_name} \{path} -> \{status_name(status)} (\{duration_ms.unwrap()}ms)\{error_suffix(err)}\n"
  }
}

///|
struct LoggingResponseWriter {
  inner : &@moonback.ResponseWriter
  mut status : Int?
}

///|
fn LoggingResponseWriter::new(
  inner : &@moonback.ResponseWriter,
) -> LoggingResponseWriter {
  { inner, status: None }
}

///|
pub impl @io.Writer for LoggingResponseWriter with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  self.inner.write_once(buf, offset~, len~)
}

///|
pub impl @moonback.ResponseWriter for LoggingResponseWriter with write_head(
  self,
  code,
  headers?,
) {
  self.status = Some(code)
  self.inner.write_head(code, headers?)
}

///|
pub impl @moonback.ResponseWriter for LoggingResponseWriter with flush(self) {
  self.inner.flush()
}

///|
async fn write_log(
  out : &@io.Writer,
  format : (
    Int64,
    String,
    String,
    String,
    Int?,
    UInt64,
    UInt64?,
    Int64?,
    Error?,
  ) -> String,
  request_id : Int64,
  phase : String,
  meth_name : String,
  path : String,
  status : Int?,
  started_at_ms : UInt64,
  ended_at_ms : UInt64?,
  duration_ms : Int64?,
  err : Error?,
) -> Unit {
  ignore(
    try? out.write(
      format(
        request_id, phase, meth_name, path, status, started_at_ms, ended_at_ms, duration_ms,
        err,
      ),
    ),
  )
}

///|
pub fn new(
  out : &@io.Writer,
  format? : (
    Int64,
    String,
    String,
    String,
    Int?,
    UInt64,
    UInt64?,
    Int64?,
    Error?,
  ) -> String = default_format,
  slow_threshold_ms? : Int = 100,
) -> @moonback.Middleware {
  @moonback.Middleware((_config, next) => {
    (r, w) => {
      let request_id = next_request_id()
      let meth_name = method_name(r.meth)
      let started_at_wall_ms = @env.now()
      let started_at_monotonic_ms = @async.now()
      let finished : Ref[Bool] = Ref::new(false)
      let slow_started : Ref[Bool] = Ref::new(false)
      let logging_writer = LoggingResponseWriter::new(w)
      let timer = @async.Timer::new(slow_threshold_ms)

      @async.with_task_group(group => {
        group.spawn_bg(allow_failure=true, () => {
          timer.wait() catch {
            @async.TimerCancelled => return
            err => raise err
          }
          if !finished.val {
            slow_started.val = true
            write_log(
              out,
              format,
              request_id,
              "start",
              meth_name,
              r.path,
              logging_writer.status,
              started_at_wall_ms,
              None,
              None,
              None,
            )
          }
        })

        next(r, logging_writer) catch {
          err => {
            finished.val = true
            timer.cancel()
            let ended_at_wall_ms = @env.now()
            let ended_at_monotonic_ms = @async.now()
            let duration_ms = ended_at_monotonic_ms - started_at_monotonic_ms
            write_log(
              out,
              format,
              request_id,
              if slow_started.val {
                "end"
              } else {
                "complete"
              },
              meth_name,
              r.path,
              logging_writer.status,
              started_at_wall_ms,
              Some(ended_at_wall_ms),
              Some(duration_ms),
              Some(err),
            )
            raise err
          }
        }

        finished.val = true
        timer.cancel()
        let ended_at_wall_ms = @env.now()
        let ended_at_monotonic_ms = @async.now()
        let duration_ms = ended_at_monotonic_ms - started_at_monotonic_ms
        write_log(
          out,
          format,
          request_id,
          if slow_started.val {
            "end"
          } else {
            "complete"
          },
          meth_name,
          r.path,
          logging_writer.status,
          started_at_wall_ms,
          Some(ended_at_wall_ms),
          Some(duration_ms),
          None,
        )
      })
    }
  })
}
