///|
pub struct App {
  priv inst : AppInstance
  priv mut serving : ServingState?

  async fn new(root : Module, config? : Config) -> App
}

///|
priv struct ServingState {
  listener : &Listener
  group : @async.TaskGroup[Unit]
  no_protect : @async.CondVar
  stopped : @async.CondVar
}

///|
pub async fn App::new(
  root : Module,
  config? : Config = Config::default(),
) -> App {
  let inst = AppInstance::init(root, config)
  { inst, serving: None }
}

///|
pub fn App::config(self : App) -> Config {
  self.inst.config
}

///|
pub impl Disposable for App with dispose(self) {
  self.inst.dispose()
}

///|
pub async fn App::handle_request(
  self : App,
  req : Request,
  w : &ResponseWriter,
) -> Unit {
  self.inst.handle_request(req, w)
}

///|
pub fn App::as_handler(self : App) -> Handler {
  (req, w) => self.handle_request(req, w)
}

///|
async fn App::serve_on_connection(
  self : App,
  conn : @http.ServerConnection,
  peer_addr : @socket.Addr,
  no_protect~ : @async.CondVar,
) -> Unit {
  for ;; {
    let req = conn.read_request()
    let req : Request = {
      ctx: {
        config: self.inst.config,
        peer_addr,
        userdata: @immut/sorted_map.SortedMap::new(),
      },
      meth: req.meth,
      path: req.path,
      headers: req.headers,
      body: conn,
    }
    @async.protect_from_cancel(() => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          no_protect.wait()
          group.return_immediately(())
        })
        self.handle_request(req, conn)
        conn.end_response()
      })
    })
  }
}

///|
async fn App::serve_on_listener(
  self : App,
  listener : &Listener,
  no_protect~ : @async.CondVar,
) -> Unit {
  @async.with_task_group(group => {
    if self.inst.config.max_connections is Some(limit) {
      let limit = @async.Semaphore::new(limit)
      for ;; {
        let (conn, peer_addr) = listener.accept()
        limit.acquire()
        group.spawn_bg(allow_failure=true, () => {
          defer {
            conn.close()
            limit.release()
          }
          self.serve_on_connection(conn, peer_addr, no_protect~)
        })
      }
    } else {
      for ;; {
        let (conn, peer_addr) = listener.accept()
        group.spawn_bg(allow_failure=true, () => {
          defer conn.close()
          self.serve_on_connection(conn, peer_addr, no_protect~)
        })
      }
    }
  })
}

///|
pub async fn App::serve(self : App, listener : &Listener) -> Unit {
  guard self.serving is None else { panic() }
  let no_protect = @async.CondVar::new()
  let stopped = @async.CondVar::new()
  @async.with_task_group(group => {
    self.serving = Some({ listener, group, no_protect, stopped })
    self.serve_on_listener(listener, no_protect~)
  })
  self.serving = None
  stopped.broadcast()
}

///|
pub async fn App::shutdown(self : App, timeout? : Double = 30) -> Unit {
  if self.serving is Some({ listener, group, no_protect, stopped }) {
    listener.close()
    group.return_immediately(())
    @async.with_timeout((timeout * 1000).to_int(), () => {
      if self.serving is Some(_) {
        stopped.wait()
      }
    }) catch {
      @async.TimeoutError => {
        no_protect.broadcast()
        stopped.wait()
      }
      err => raise err
    }
  }
}
