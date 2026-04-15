///|
priv struct Router {
  tree : Trie[Route]
}

///|
pub suberror RouterError {
  /// Raised when route registration fails.
  RouteConflict(path~ : StringView)
}

///|
priv struct Route {
  mut get : Handler?
  mut post : Handler?
  other : Array[(@http.RequestMethod, Handler)]
  mut fallback : Handler?
}

///|
fn Route::new() -> Route {
  { get: None, post: None, other: [], fallback: None }
}

///|
fn Route::handler_for(self : Route, meth : @http.RequestMethod) -> Handler? {
  match meth {
    Get =>
      match self.get {
        Some(handler) => Some(handler)
        None => self.fallback
      }
    Post =>
      match self.post {
        Some(handler) => Some(handler)
        None => self.fallback
      }
    _ => {
      for pair in self.other {
        let (candidate, handler) = pair
        if candidate == meth {
          return Some(handler)
        }
      }
      self.fallback
    }
  }
}

///|
fn Route::add_handler(
  self : Route,
  meth : @http.RequestMethod,
  handler : Handler,
) -> Unit raise RouterError {
  match meth {
    Get =>
      match self.get {
        Some(_) => raise RouteConflict(path="")
        None => self.get = Some(handler)
      }
    Post =>
      match self.post {
        Some(_) => raise RouteConflict(path="")
        None => self.post = Some(handler)
      }
    _ => {
      for pair in self.other {
        let (candidate, _) = pair
        if candidate == meth {
          raise RouteConflict(path="")
        }
      }
      self.other.push((meth, handler))
    }
  }
}

///|
fn Route::add_handler_with_path(
  self : Route,
  meth : @http.RequestMethod,
  path : StringView,
  handler : Handler,
) -> Unit raise RouterError {
  self.add_handler(meth, handler) catch {
    RouteConflict(_) => raise RouteConflict(path~)
  }
}

///|
fn Route::add_fallback(
  self : Route,
  handler : Handler,
) -> Unit raise RouterError {
  match self.fallback {
    Some(_) => raise RouteConflict(path="")
    None => self.fallback = Some(handler)
  }
}

///|
fn Route::add_fallback_with_path(
  self : Route,
  path : StringView,
  handler : Handler,
) -> Unit raise RouterError {
  self.add_fallback(handler) catch {
    RouteConflict(_) => raise RouteConflict(path~)
  }
}

///|
fn Router::new() -> Router {
  { tree: Trie::root() }
}

///|
fn Router::route_for_path(
  self : Router,
  path : StringView,
) -> (Route, Map[StringView, StringView])? {
  match self.tree.search(path) {
    None => None
    Some({ payload, params }) => Some((payload, params))
  }
}

///|
fn Router::put_route(
  self : Router,
  path : StringView,
  update : (Route) -> Unit raise RouterError,
) -> Unit raise RouterError {
  let route = match self.route_for_path(path) {
    Some((route, _)) => route
    None => Route::new()
  }
  update(route)
  self.tree.insert(path, route)
}

///|
fn Router::add_route(
  self : Router,
  meth : @http.RequestMethod,
  path : StringView,
  handler : Handler,
) -> Unit raise RouterError {
  self.put_route(path, route => route.add_handler_with_path(meth, path, handler))
}

///|
fn Router::add_fallback_route(
  self : Router,
  path : StringView,
  handler : Handler,
) -> Unit raise RouterError {
  self.put_route(path, route => route.add_fallback_with_path(path, handler))
}

///|
priv struct RouteResult {
  handler : Handler
  params : Map[StringView, StringView]
}

///|
fn Router::route(
  self : Router,
  meth : @http.RequestMethod,
  path : StringView,
) -> RouteResult? {
  match self.route_for_path(path) {
    None => None
    Some((route, params)) =>
      match route.handler_for(meth) {
        None => None
        Some(handler) => Some({ handler, params })
      }
  }
}
