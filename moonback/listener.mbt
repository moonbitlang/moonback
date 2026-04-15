///|
///  A trait for accepting incoming network connections.
///
/// Implementations of this trait are responsible for listening on a network socket
/// and accepting new client connections.
///
/// ## Methods
///
/// * `accept` - Asynchronously waits for and accepts the next incoming connection.
///   Returns a tuple containing the established HTTP server connection and the
///   client's socket address.
///
/// * `close` - Closes the listener and stops accepting new connections.
pub(open) trait Listener {
  async accept(self : Self) -> (@http.ServerConnection, @socket.Addr)
  close(self : Self) -> Unit
}

///|
pub impl Listener for @http.Server with accept(self) {
  self.accept()
}

///|
pub impl Listener for @http.Server with close(self) {
  self.close()
}
