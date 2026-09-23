///|
priv suberror ClientDisconnected

///|
priv struct CloseHandler {
  id : Int
  handler : () -> Unit
}

///|
priv struct TrackedServerConnection {
  conn : @http.ServerConnection
  mut client_disconnected : Bool
  mut unusable : Bool
  mut next_close_handler_id : Int
  mut close_handlers : Array[CloseHandler]
}

///|
fn TrackedServerConnection::new(
  conn : @http.ServerConnection,
) -> TrackedServerConnection {
  {
    conn,
    client_disconnected: false,
    unusable: false,
    next_close_handler_id: 0,
    close_handlers: [],
  }
}

///|
fn TrackedServerConnection::is_client_disconnected(
  self : TrackedServerConnection,
) -> Bool {
  self.client_disconnected
}

///|
fn TrackedServerConnection::is_unusable(self : TrackedServerConnection) -> Bool {
  self.unusable
}

///|
fn TrackedServerConnection::on_close(
  self : TrackedServerConnection,
  f : () -> Unit,
) -> () -> Unit {
  if self.client_disconnected {
    f()
    () => ()
  } else {
    let id = self.next_close_handler_id
    self.next_close_handler_id += 1
    self.close_handlers.push({ id, handler: f, })
    () => {
      guard self.close_handlers.search_by(h => h.id == id) is Some(idx) else {
        return
      }
      let _ = self.close_handlers.remove(idx)
    }
  }
}

///|
fn TrackedServerConnection::notify_client_disconnected(
  self : TrackedServerConnection,
) -> Unit {
  self.unusable = true
  if !self.client_disconnected {
    self.client_disconnected = true
    let handlers = self.close_handlers
    self.close_handlers = []
    for h in handlers {
      (h.handler)()
    }
  }
}

///|
fn TrackedServerConnection::notify_unusable(
  self : TrackedServerConnection,
) -> Unit {
  self.unusable = true
}

///|
async fn TrackedServerConnection::read_request(
  self : TrackedServerConnection,
) -> @http.Request {
  errdefer self.notify_unusable()
  self.conn.read_request() catch {
    @io.ReaderClosed | @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
async fn TrackedServerConnection::send_response(
  self : TrackedServerConnection,
  code : Int,
  reason : String,
  extra_headers? : @http.Headers = Map([]),
  cookies? : Array[@http.Cookie] = [],
) -> Unit {
  errdefer self.notify_unusable()
  self.conn.send_response(code, reason, extra_headers~, cookies~) catch {
    @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
async fn TrackedServerConnection::end_response(
  self : TrackedServerConnection,
) -> Unit {
  errdefer self.notify_unusable()
  self.conn.end_response() catch {
    @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
async fn TrackedServerConnection::upgrade(
  self : TrackedServerConnection,
  req : @http.Request,
) -> @websocket.Conn {
  errdefer self.notify_unusable()
  @websocket.from_http_server(req, self.conn) catch {
    @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
async fn TrackedServerConnection::flush(self : TrackedServerConnection) -> Unit {
  errdefer self.notify_unusable()
  self.conn.flush() catch {
    @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
impl @io.Reader for TrackedServerConnection with fn _get_internal_buffer(self) {
  @io.Reader::_get_internal_buffer(self.conn)
}

///|
impl @io.Reader for TrackedServerConnection with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  errdefer self.notify_unusable()
  @io.Reader::_direct_read(self.conn, buf, offset~, max_len~) catch {
    @io.ReaderClosed | @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
impl @io.Writer for TrackedServerConnection with fn write_once(
  self,
  buf,
  offset~,
  len~,
) {
  errdefer self.notify_unusable()
  self.conn.write_once(buf, offset~, len~) catch {
    @os_error.OSError(_) => {
      self.notify_client_disconnected()
      raise ClientDisconnected
    }
    err => raise err
  }
}

///|
impl Flusher for TrackedServerConnection with fn flush(self) {
  self.flush()
}

///|
impl WriteFlusher for TrackedServerConnection
