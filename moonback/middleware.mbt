///|
pub(all) struct Middleware((Config, Handler) -> Handler)

///|
pub fn Middleware::pass_through() -> Middleware {
  Middleware((_config, next) => next)
}

///|
pub fn Middleware::compose(self : Middleware, other : Middleware) -> Middleware {
  Middleware((config, next) => (self.0)(config, (other.0)(config, next)))
}

///|
pub fn Middleware::chain(middlewares : ArrayView[Middleware]) -> Middleware {
  match middlewares {
    [] => Middleware((_config, next) => next)
    [first, .. rest] => first.compose(Middleware::chain(rest))
  }
}
