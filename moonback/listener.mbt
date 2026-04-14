///|
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
