///|
/// A writer that also supports flushing buffered output.
pub(open) trait WriteFlusher: @io.Writer + Flusher {}

///|
/// Flushes buffered output to the underlying transport.
pub(open) trait Flusher {
  async flush(self : Self) -> Unit
}

///|
/// Creates an HTTP server listener bound to the given host (IP address only) and port.
///
/// If `host` is the IPv6 wildcard address `[::]`
/// and `dual_stack` is `true` (`true` by default),
/// the server will work in dual stack mode,
/// accepting connections from both IPv4 clients and IPv6 clients.
/// The address of IPv4 clients are represented via IPv4-mapped IPv6 address.
///
/// If `host` is not `[::]`, `dual_stack` is ignored.
///
/// If the port of `host` is zero, the server will be bound to a random port,
/// assigned by the operating system.
/// The actual listen address can be retrieved via `.addr()`.
///
/// If `reuse_addr` is `true` (`true` by default),
/// the `SO_REUSEADDR` option will be enabled on the server,
/// allowing in currently-in-use socket address
/// (as long as there is no one else currently listening on the same address).
/// This is useful for avoiding "address already in use" error.
pub async fn listen(
  reuse_addr? : Bool = true,
  dual_stack? : Bool = true,
  host? : String = "127.0.0.1",
  port? : UInt16 = 0,
) -> @http.Server {
  let addr = @socket.Addr::parse(join_host_port(host, port))
  @http.Server::new(addr, dual_stack~, reuse_addr~)
}
