///|
pub let default_handler : Handler = (_, w) => w.write_head(404)

///|
pub let mock_context : Context = Context::mock()

///|
pub async fn listen(
  reuse_addr? : Bool = true,
  dual_stack? : Bool = true,
  host? : String = "127.0.0.1",
  port? : UInt16 = 0,
) -> @http.Server {
  let addr = @socket.Addr::parse(join_host_port(host, port))
  @http.Server::new(addr, dual_stack~, reuse_addr~)
}
