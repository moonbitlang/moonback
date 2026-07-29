///|
struct ModuleContext {
  inst : AppInst
}

///|
/// A `Module` is a reusable unit of app initialization.
///
/// A module runs once when an `App` is created. Inside the module you use
/// `ModuleContext` to describe one slice of the application, for example:
///
/// - register routes
/// - append middlewares
/// - mount sub-apps
/// - register cleanup hooks with `on_close`
///
/// This is the main mechanism for splitting business logic into small,
/// composable pieces. A feature such as `auth`, `admin`, `blog api`, or
/// `payments` can each be modeled as a module and then assembled into a root
/// module.
///
/// Because modules are plain values, they are easy to:
///
/// - compose with other modules
/// - reuse across multiple apps
/// - encapsulate feature-specific setup
/// - test in isolation by creating an app from just that module
///
/// `Module` focuses on describing application structure, not starting the
/// server. Server startup still happens through `App::serve`.
///
/// Example:
/// ```moonbit nocheck
/// let posts_module = Module(ctx => {
///   ctx.get("/posts", list_posts)
///   ctx.get("/posts/:id", show_post)
/// })
///
/// let admin_module = Module(ctx => {
///   ctx.add_middleware(require_admin)
///   ctx.get("/users", list_users)
/// })
///
/// let root = Module(ctx => {
///   ctx.use_(posts_module)
///   ctx.use_(admin_module)
/// })
///
/// let app = @moonback.App(root)
/// ```
pub(all) struct Module(async (ModuleContext) -> Unit)

///|
/// Implemented by values that can extend a module context during initialization.
///
/// `Module` implements this trait, so `ctx.use_(some_module)` works directly.
/// Custom extension values can also implement `Extension` when you want to
/// package reusable setup logic without exposing it as a raw module.
pub(open) trait Extension {
  async fn initialize(self : Self, ctx : ModuleContext) -> Unit
}

///|
/// Returns the configuration for the app being initialized.
pub fn ModuleContext::config(self : ModuleContext) -> Config {
  self.inst.config
}

///|
/// Registers a callback that runs when the owning app is closed.
pub fn ModuleContext::on_close(self : ModuleContext, f : () -> Unit) -> Unit {
  self.inst.close_hook.push(f)
}

///|
/// Mounts another app under `path`.
/// When `take_ownership` is true (`true` by default), the mounted app is closed
/// with the parent.
pub fn ModuleContext::mount(
  self : ModuleContext,
  path : String,
  app : App,
  take_ownership? : Bool = true,
) -> Unit raise RouterError {
  if take_ownership {
    self.on_close(() => app.close())
  }
  let path = mount_path(path)
  self.inst.router.add_fallback_route(path, (req, res) => {
    app.handle_request({ ..req, path: "/", params: {} }, res)
  })
  let prefix = if path == "/" { "/" } else { path + "/" }
  self.inst.router.add_fallback_route(prefix + "*path", (req, res) => {
    let path = mounted_request_path(req.params["path"])
    app.handle_request({ ..req, path, params: {} }, res)
  })
}

///|
fn mount_path(path : String) -> String {
  if path.is_empty() {
    "/"
  } else if path.length() > 1 && path.has_suffix("/") {
    path[0:path.length() - 1].to_owned()
  } else {
    path
  }
}

///|
fn mounted_request_path(path : StringView) -> String {
  if path.is_empty() {
    "/"
  } else if path.has_prefix("/") {
    path.to_owned()
  } else {
    "/" + path.to_owned()
  }
}

///|
/// Applies an extension to the current module context.
///
/// This is the composition point for modules. The extension is initialized
/// immediately and can keep registering routes, middlewares, mounts, and close
/// hooks on the current app.
///
/// The most common use is composing feature modules:
///
/// ```moonbit nocheck
/// let api = Module(ctx => ctx.get("/health", health_handler))
///
/// let root = Module(ctx => ctx.use_(api))
/// ```
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
pub impl Extension for Module with fn initialize(self, ctx) {
  self(ctx)
}

///|
pub extend Module with Extension::{initialize}
