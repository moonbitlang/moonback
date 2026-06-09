///|
/// A responder is newtype of an asynchronous function that takes a status code
/// and headers, sends the response status line and headers, and returns a writer
/// for the response body.
///
/// **Important Notes**: The responder is only valid during request handling.
/// Do not store it or use it after the response cycle completes.
pub(all) struct Responder(async (Int, Headers) -> &WriteFlusher)

///|
impl WriteFlusher for @http.ServerConnection

///|
#warnings("-unused_value")
impl Flusher for @http.ServerConnection with fn flush(self) {
  self.flush()
}

///|
fn Responder::from_conn(conn : @http.ServerConnection) -> Responder {
  Responder((status, h) => {
    // TODO: raise error if upgraded
    conn.send_response(
      status,
      status_to_reason_phrase(status),
      extra_headers=h.store.headers,
      cookies=h.store.set_cookie.map(str => parse_set_cookie(str)),
    )
    conn
  })
}

///|
/// Sends the status line and headers, then returns the body writer.
pub async fn Responder::respond(
  self : Responder,
  status? : Int = 200,
  headers? : &ToHeaders,
) -> &WriteFlusher {
  (self.0)(
    status,
    match headers {
      None => Headers::default()
      Some(h) => h.to_headers()
    },
  )
}

///|
/// Sends a response without writing a body.
pub async fn Responder::send_void(
  self : Responder,
  status? : Int = 200,
  headers? : &ToHeaders,
) -> Unit {
  let _ = self.respond(status~, headers?)
}

///|
/// Sends a JSON response with the appropriate content type.
pub async fn Responder::send_json(
  self : Responder,
  json : Json,
  status? : Int = 200,
  headers? : &ToHeaders,
  indent? : Int,
) -> Unit {
  self
  .respond(
    status~,
    headers=[
      ("Content-Type", "application/json"),
      ..iter_optional_to_headers(headers),
    ],
  )
  .write(json.stringify(indent?))
}

///|
/// Sends a plain text response with UTF-8 content type.
pub async fn Responder::send_text(
  self : Responder,
  text : String,
  status? : Int = 200,
  headers? : &ToHeaders,
) -> Unit {
  self
  .respond(
    status~,
    headers=[
      ("Content-Type", "text/plain; charset=utf-8"),
      ..iter_optional_to_headers(headers),
    ],
  )
  .write(text)
}

///|
/// Sends an HTML response with UTF-8 content type.
pub async fn Responder::send_html(
  self : Responder,
  html : Html,
  status? : Int = 200,
  headers? : &ToHeaders,
) -> Unit {
  self
  .respond(
    status~,
    headers=[
      ("Content-Type", "text/html; charset=utf-8"),
      ..iter_optional_to_headers(headers),
    ],
  )
  .write(html.raw())
}

///|
/// Upgrades the current HTTP connection to a WebSocket connection.
///
/// Returns A WebSocket connection object for bidirectional communication.
///
/// **Important Notes**
/// - After upgrading, do not send an HTTP response. Use the WebSocket connection
///   to communicate with the client instead.
/// - The returned WebSocket connection is only valid during request handling.
///   Do not store it or use it after the response cycle completes.
pub async fn Responder::upgrade(
  _self : Responder,
  req : Request,
) -> @websocket.Conn {
  match req.ctx.conn_info {
    Mock => fail("Mock")
    Normal(raw_req, server_conn, peer_addr) => {
      let ws = @websocket.from_http_server(raw_req, server_conn)
      req.ctx.conn_info = Upgraded(ws, peer_addr)
      ws
    }
    Upgraded(_) => fail("Upgraded")
  }
}
