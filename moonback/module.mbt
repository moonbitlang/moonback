///|
struct ModuleContext {
  inst : AppInstance
}

///|
pub(all) struct Module(async (ModuleContext) -> Unit)

///|
pub fn ModuleContext::add_disposer(
  self : ModuleContext,
  disposer : &Disposable,
) -> Unit {
  self.inst.disposables.push(disposer)
}

///|
pub fn ModuleContext::use_(
  self : ModuleContext,
  middleware : Middleware,
) -> Unit {
  self.inst.middlewares.push(middleware)
}

///|
pub fn ModuleContext::get(
  self : ModuleContext,
  path : String,
  handler : Handler,
) -> Unit raise RouterError {
  self.inst.router.add_route(Get, path, handler)
}

///|
pub fn ModuleContext::post(
  self : ModuleContext,
  path : String,
  handler : Handler,
) -> Unit raise RouterError {
  self.inst.router.add_route(Post, path, handler)
}

///|
pub fn ModuleContext::add_route(
  self : ModuleContext,
  meth : @http.RequestMethod,
  path : String,
  handler : Handler,
) -> Unit raise RouterError {
  self.inst.router.add_route(meth, path, handler)
}
