///|
struct ModuleContext {
  inst : AppInst
}

///|
/// Represents a reusable application module that registers routes and hooks.
pub(all) struct Module(async (ModuleContext) -> Unit)

///|
/// Implemented by values that can extend a module context during initialization.
pub(open) trait Extension {
  async initialize(self : Self, ctx : ModuleContext) -> Unit
}

///|
/// Registers a callback that runs when the owning app is closed.
pub fn ModuleContext::on_close(self : ModuleContext, f : () -> Unit) -> Unit {
  self.inst.close_hook.push(f)
}

///|
/// Mounts another app under `path`.
/// When `take_ownership` is true, the mounted app is closed with the parent.
pub fn ModuleContext::mount(
  self : ModuleContext,
  path : String,
  app : App,
  take_ownership? : Bool = true,
) -> Unit raise RouterError {
  if take_ownership {
    self.on_close(() => app.close())
  }
  let path = if path.has_suffix("/") { path } else { path + "/" }
  self.inst.router.add_fallback_route(path + "*path", (req, res) => {
    let path = req.params["path"]
    app.handle_request({ ..req, path, params: {} }, res)
  })
}

///|
/// Applies an extension to the current module context.
pub async fn ModuleContext::use_(
  self : ModuleContext,
  ext : &Extension,
) -> Unit {
  ext.initialize(self)
}

///|
/// Registers a `GET` route.
pub fn ModuleContext::get(
  self : ModuleContext,
  path : String,
  handler : Handler,
) -> Unit raise RouterError {
  self.inst.router.add_route(Get, path, handler)
}

///|
/// Registers a `POST` route.
pub fn ModuleContext::post(
  self : ModuleContext,
  path : String,
  handler : Handler,
) -> Unit raise RouterError {
  self.inst.router.add_route(Post, path, handler)
}

///|
/// Registers a route for the given HTTP method and path.
pub fn ModuleContext::add_route(
  self : ModuleContext,
  meth : @http.RequestMethod,
  path : String,
  handler : Handler,
) -> Unit raise RouterError {
  self.inst.router.add_route(meth, path, handler)
}

///|
/// Appends a middleware to the current app.
pub fn ModuleContext::add_middleware(
  self : ModuleContext,
  middleware : Middleware,
) -> Unit {
  self.inst.middlewares.push(middleware)
}

///|
pub impl Extension for Module with initialize(self, ctx) {
  self(ctx)
}
