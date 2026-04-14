///|
priv struct AppInstance {
  config : Config
  router : Router
  mut middlewares : Array[Middleware]
  mut disposables : Array[&Disposable]
}

///|
async fn AppInstance::init(root : Module, config : Config) -> AppInstance {
  let inst : AppInstance = {
    config,
    router: Router::new(),
    middlewares: [],
    disposables: [],
  }
  (root.0)({ inst, })
  inst
}

///|
impl Disposable for AppInstance with dispose(self) {
  self.middlewares = []
  let disposables = self.disposables
  self.disposables = []
  for disposable in disposables {
    disposable.dispose()
  }
  guard self.disposables.is_empty() else { panic() }
}

///|
async fn AppInstance::handle_request(
  self : AppInstance,
  r : Request,
  w : &ResponseWriter,
) -> Unit {
  let handler = match self.router.route(r.meth, r.path) {
    None => default_handler
    Some({ handler, .. }) => handler
  }
  Middleware::chain(self.middlewares)(self.config, handler)(r, w) catch {
    StopResponding => ()
    err => raise err
  }
}
