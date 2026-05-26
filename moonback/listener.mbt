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
  async fn accept(self : Self) -> (@http.ServerConnection, @socket.Addr)
  fn close(self : Self) -> Unit
}

///|
pub impl Listener for @http.Server with fn accept(self) {
  self.accept()
}

///|
pub impl Listener for @http.Server with fn close(self) {
  self.close()
}
