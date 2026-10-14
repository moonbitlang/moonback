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
/// Cancels the wrapped handler when the request's serving app begins shutdown.
/// Long-lived streams and WebSocket handlers can use this to stop without
/// waiting for `Config.stop_timeout`. Handler `defer` and `errdefer` blocks
/// still run; async cleanup can use `@async.protect_from_cancel`.
/// Interrupted HTTP connections are closed without finalizing the response.
/// Apply it to a single handler with `Middleware::apply`, or register it with
/// `ModuleContext::add_middleware` for every request.
pub fn cancel_on_shutdown() -> Middleware {
  next => {
    (req, res) => {
      @async.with_task_group(group => {
        group.spawn_bg(
          () => {
            req.app().wait_for_shutdown_requested()
            // return_immediately cancels next but returns normally to the caller.
            // Close the interrupted HTTP response instead of ending or reusing it.
            match req.ctx.conn_info {
              Normal(_, conn, _) => conn.notify_unusable()
              Mock | Upgraded(_, _) => ()
            }
            group.return_immediately(())
          },
          no_wait=true,
        )
        next(req, res)
      })
    }
  }
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

///|
/// Wraps a handler with this middleware.
/// Use this to apply middleware to an individual route handler.
pub fn Middleware::apply(self : Middleware, handler : Handler) -> Handler {
  (self.0)(handler)
}
