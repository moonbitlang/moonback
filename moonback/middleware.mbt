///|
/// A middleware is a newtype of a function that takes a next handler, and returns a new handler.
/// Example:
/// ```moonbit nocheck
/// let auth_middleware = Middleware(next => {
///   (req, res) => {
///     if is_authenticated(req) {
///       next(req, res)
///     } else {
///       res.send_void(status=401)
///     }
///   }
/// })
/// ```
pub(all) struct Middleware((Handler) -> Handler)

///|
/// Returns a middleware that forwards requests without modification.
pub fn Middleware::pass_through() -> Middleware {
  Middleware(next => next)
}

///|
/// Composes two middlewares into one.
/// The current middleware runs before `other`.
pub fn Middleware::compose(self : Middleware, other : Middleware) -> Middleware {
  Middleware(next => (self.0)((other.0)(next)))
}

///|
/// Chains middlewares in declaration order.
pub fn Middleware::chain(middlewares : ArrayView[Middleware]) -> Middleware {
  match middlewares {
    [] => Middleware(next => next)
    [first, .. rest] => first.compose(Middleware::chain(rest))
  }
}
