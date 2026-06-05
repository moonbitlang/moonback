///|
priv struct AppInst {
  config : Config
  router : Router
  mut middlewares : Array[Middleware]
  mut close_hook : Array[() -> Unit]
  mut dependencies : @immut/sorted_map.SortedMap[Int, Error]
}

///|
/// A configured application that can handle requests and serve listeners.
pub struct App {
  priv inst : AppInst
}

///|
async fn AppInst::init(root : Module, config : Config) -> AppInst {
  let inst : AppInst = {
    config,
    router: Router::new(),
    middlewares: [],
    close_hook: [],
    dependencies: @immut/sorted_map.SortedMap::new(),
  }
  (root.0)({ inst, })
  inst
}

///|
fn AppInst::on_close(self : AppInst) -> Unit {
  self.middlewares = []
  let funcs = self.close_hook
  self.close_hook = []
  for func in funcs.rev() {
    func()
  }
  guard self.close_hook.is_empty() else { panic() }
  self.dependencies = @immut/sorted_map.SortedMap::new()
}

///|
async fn AppInst::handle_request(
  self : AppInst,
  req : Request,
  res : Responder,
) -> Unit {
  let handler = match self.router.route(req.meth, req.path) {
    None => default_handler
    Some({ handler, params }) => (req, res) => handler({ ..req, params, }, res)
  }
  Middleware::chain(self.middlewares)(handler)(req, res) catch {
    StopResponding => ()
    _err => res.send_void(status=500)
    // TODO: log the error
  }
}

///|
/// Creates an app from the root module and configuration.
///
/// The root module is the composition entry of the application. It can register
/// routes directly, or assemble the app from smaller reusable modules through
/// `ModuleContext::use_`.
///
/// This returns after the root module has finished loading.
pub async fn App::App(
  root : Module,
  config? : Config = Config::default(),
) -> App {
  let inst = AppInst::init(root, config)
  { inst, }
}

///|
/// Returns the application's configuration.
pub fn App::config(self : App) -> Config {
  self.inst.config
}

///|
/// Handles a prepared request with this app.
pub async fn App::handle_request(
  self : App,
  req : Request,
  res : Responder,
) -> Unit {
  self.inst.handle_request(req, res)
}

///|
async fn App::serve_on_connection(
  self : App,
  conn : @http.ServerConnection,
  peer_addr : @socket.Addr,
  no_protect~ : @async.CondVar,
) -> Unit {
  let mut upgraded = false
  for ; !upgraded; {
    @async.protect_from_cancel(() => {
      @async.with_task_group(group => {
        let req = conn.read_request()
        let (path, search) = split_path_search(req.path)
        let req : Request = {
          ctx: Context::new(self, Normal(req, conn, peer_addr)),
          meth: req.meth,
          path,
          search,
          headers: Headers::from_request(req.headers),
          params: {},
          body: RequestBody::from_ready_stream(conn, group~),
        }
        group.spawn_bg(no_wait=true, () => {
          no_protect.wait()
          group.return_immediately(())
        })
        self.handle_request(req, Responder::from_conn(conn))
        if req.ctx.conn_info is Upgraded(_, _) {
          upgraded = true
        } else {
          conn.end_response()
        }
      })
    })
  }
}

///|
/// Starts accepting connections from `listener` and serves requests on them.
/// This returns when serving stops or when the surrounding task is cancelled.
///
/// If `take_ownership` is true (`true` by default), `listener.close()` is
/// called / before returning.
///
/// On cancellation, in-flight connections are given up to
/// `Config.stop_timeout` seconds to finish gracefully.
pub async fn App::serve(
  self : App,
  listener : &Listener,
  take_ownership? : Bool = true,
) -> Unit {
  let no_protect = @async.CondVar::new()
  @async.with_task_group(group => {
    try {
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
      if take_ownership {
        listener.close()
      }
    } catch {
      err => {
        if take_ownership {
          listener.close()
        }
        if @async.is_cancellation_error(err) &&
          self.inst.config.stop_timeout is timeout &&
          timeout > 0 {
          group.spawn_bg(() => {
            @async.sleep((timeout * 1000).to_int())
            no_protect.broadcast()
          })
        } else {
          no_protect.broadcast()
        }
        raise err
      }
    }
  })
}

///|
/// Unload root module - run registered on_close hooks.
/// The app should not be used after this.
///
/// Example:
/// ```moonbit nocheck
/// let app = @moonback.App((ctx) => { ... })
/// defer app.close()
/// app.serve(@moonback.listen())
/// ```
pub fn App::close(self : App) -> Unit {
  self.inst.on_close()
}
