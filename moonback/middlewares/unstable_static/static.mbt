///|
priv enum PathStatus {
  Missing
  Forbidden
  Kind(@fs.FileKind)
}

///|
priv enum ServedPath {
  Missing
  Forbidden
  Found(String)
}

///|
let default_missing_handler : @moonback.Handler = (_req, res) => {
  res.send_void(status=404)
}

///|
priv suberror HistoryFallback

///|
fn strip_query_and_fragment(path : StringView) -> String {
  let mut end = path.length()
  if path.find("?") is Some(index) && index < end {
    end = index
  }
  if path.find("#") is Some(index) && index < end {
    end = index
  }
  path[:end].to_string()
}

///|
fn has_trailing_slash(path : String) -> Bool {
  match path {
    [.., '/'] => true
    _ => false
  }
}

///|
fn normalize_relative_path(path : String) -> String? {
  guard path.has_prefix("/") else { return None }
  let segments = []
  for segment in path.split("/").collect() {
    match segment {
      "" | "." => ()
      ".." => return None
      segment => segments.push(segment.to_string())
    }
  }
  Some(segments.join("/"))
}

///|
fn join_path(base : String, relative : String) -> String {
  guard base != "" else { return relative }
  match base {
    [.., '/'] | [.., '\\'] => base + relative
    _ => "\{base}/\{relative}"
  }
}

///|
fn guess_content_type(path : String) -> String {
  match path.to_lower() {
    [.., .. ".html"] => "text/html; charset=utf-8"
    [.., .. ".css"] => "text/css; charset=utf-8"
    [.., .. ".js"] => "text/javascript; charset=utf-8"
    [.., .. ".mjs"] => "text/javascript; charset=utf-8"
    [.., .. ".json"] => "application/json; charset=utf-8"
    [.., .. ".txt"] => "text/plain; charset=utf-8"
    [.., .. ".svg"] => "image/svg+xml"
    [.., .. ".png"] => "image/png"
    [.., .. ".jpg"] | [.., .. ".jpeg"] => "image/jpeg"
    [.., .. ".gif"] => "image/gif"
    [.., .. ".ico"] => "image/x-icon"
    [.., .. ".wasm"] => "application/wasm"
    [.., .. ".pdf"] => "application/pdf"
    _ => "application/octet-stream"
  }
}

///|
async fn stat_path(path : String) -> PathStatus {
  try @fs.kind(path) catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => Missing
    @os_error.OSError(_) as err if err.is_EACCES() => Forbidden
    err => raise err
  } noraise {
    kind => Kind(kind)
  }
}

///|
async fn resolve_served_file(
  base_dir : String,
  request_path : String,
  trailing_slash~ : Bool,
  rewrite_trailing_slash_index~ : Bool,
) -> ServedPath {
  let candidate = if request_path == "" {
    base_dir
  } else {
    join_path(base_dir, request_path)
  }
  match stat_path(candidate) {
    Missing => Missing
    Forbidden => Forbidden
    Kind(Regular) => Found(candidate)
    Kind(Directory) =>
      if trailing_slash && rewrite_trailing_slash_index {
        let index_path = join_path(candidate, "index.html")
        match stat_path(index_path) {
          Kind(Regular) => Found(index_path)
          Missing | Kind(_) => Missing
          Forbidden => Forbidden
        }
      } else {
        Missing
      }
    Kind(_) => Missing
  }
}

///|
fn is_history_fallback_candidate(path : String) -> Bool {
  guard path != "" else { return true }
  let last_segment = match path.rev_find("/") {
    Some(index) => path[index + 1:]
    None => path.view()
  }
  !last_segment.contains_char('.')
}

///|
async fn send_file(
  req : @moonback.Request,
  res : @moonback.Responder,
  file_path : String,
  on_missing? : @moonback.Handler = default_missing_handler,
) -> Unit {
  try {
    let file = @fs.open(file_path, mode=ReadOnly)
    defer file.close()
    let size = file.size()
    let headers = @moonback.Headers::from({
      "Content-Type": guess_content_type(file_path),
      "Content-Length": size.to_string(),
    })
    if req.meth is Head {
      res.send_void(status=200, headers~)
    } else {
      let writer = res.respond(status=200, headers~)
      writer.write_reader(file)
    }
  } catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => on_missing(req, res)
    @os_error.OSError(_) as err if err.is_EACCES() => res.send_void(status=403)
    _ => res.send_void(status=500)
  }
}

///|
fn history_fallback_responder(
  inner : @moonback.Responder,
) -> @moonback.Responder {
  (status, headers) => {
    if status == 404 {
      raise HistoryFallback
    }
    inner.respond(status~, headers~)
  }
}

///|
pub fn new(
  root~ : String,
  rewrite_trailing_slash_index? : Bool = false,
  history_fallback? : String? = None,
) -> @moonback.Middleware {
  @moonback.Middleware(next => {
    (req, res) => {
      guard req.meth is Get || req.meth is Head else {
        next(req, res)
        return
      }

      let request_path = strip_query_and_fragment(req.path)
      let trailing_slash = has_trailing_slash(request_path)
      guard normalize_relative_path(request_path) is Some(relative_path) else {
        res.send_void(status=404)
        return
      }
      match
        resolve_served_file(
          root,
          relative_path,
          trailing_slash~,
          rewrite_trailing_slash_index~,
        ) {
        Forbidden => res.send_void(status=403)
        Found(file_path) => send_file(req, res, file_path, on_missing=next)
        Missing =>
          if history_fallback is Some(fallback) &&
            is_history_fallback_candidate(relative_path) {
            guard normalize_relative_path(fallback) is Some(fallback_path) else {
              next(req, res)
              return
            }
            next(req, history_fallback_responder(res)) catch {
              HistoryFallback =>
                match
                  resolve_served_file(
                    root,
                    fallback_path,
                    trailing_slash=false,
                    rewrite_trailing_slash_index=false,
                  ) {
                  Missing => next(req, res)
                  Forbidden => res.send_void(status=403)
                  Found(file_path) => send_file(req, res, file_path)
                }
              err => raise err
            }
          } else {
            next(req, res)
          }
      }
    }
  })
}
