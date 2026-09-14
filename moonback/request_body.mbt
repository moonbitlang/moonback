///|
/// Represents the body of an HTTP request, which can be read as a stream or buffered in memory.
struct RequestBody {
  group : @async.TaskGroup[Unit]
  mut state : RequestBodyState
}

///|
priv enum RequestBodyState {
  ReadyStream(&@io.Reader)
  Unbuffered
  Buffered(@async.Task[&@io.Data])
}

///|
fn RequestBody::from_ready_stream(
  reader : &@io.Reader,
  group~ : @async.TaskGroup[Unit],
) -> RequestBody {
  { group, state: ReadyStream(reader), }
}

///|
async fn RequestBody::data(self : RequestBody) -> &@io.Data {
  match self.state {
    ReadyStream(reader) => {
      let task = self.group.spawn(() => reader.read_all())
      self.state = Buffered(task)
      task.wait()
    }
    Unbuffered =>
      fail(
        "Request body has already been read as a stream, cannot be read again",
      )
    Buffered(task) => task.wait()
  }
}

///|
/// Returns the request body as a stream reader.
/// This can only be called once, and `no_buffer=false` is not supported yet.
pub fn RequestBody::reader(
  self : RequestBody,
  no_buffer? : Bool = true,
) -> &@io.Reader raise {
  if !no_buffer {
    fail(
      "no_buffer=false is not supported for RequestBody::reader, as buffering is not implemented yet",
    )
  }
  match self.state {
    ReadyStream(reader) => {
      self.state = Unbuffered
      reader
    }
    Unbuffered =>
      fail(
        "Request body has already been read as a stream, cannot be read again",
      )
    Buffered(_task) =>
      fail("Request body has already been buffered, cannot be read as a stream")
  }
}

///|
/// Reads the full request body as raw bytes.
///
/// This buffers the entire body in memory, so it should only be used for small
/// request bodies or when the content length is known to be reasonable.
pub async fn RequestBody::binary(self : RequestBody) -> Bytes {
  self.data().binary()
}

///|
/// Reads the full request body as text.
///
/// This buffers the entire body in memory, so it should only be used for small
/// request bodies or when the content length is known to be reasonable.
pub async fn RequestBody::text(self : RequestBody) -> String {
  self.data().text()
}

///|
/// Reads the full request body and parses it as JSON.
///
/// This buffers the entire body in memory, so it should only be used for small
/// request bodies or when the content length is known to be reasonable.
pub async fn RequestBody::json(self : RequestBody) -> Json {
  self.data().json()
}
