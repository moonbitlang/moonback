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
priv suberror HistoryFallback

///|
fn strip_query_and_fragment(path : String) -> String {
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
    [.., .. ".js"] => "application/javascript"
    [.., .. ".json"] => "application/json"
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
  directory_index~ : Bool,
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
      if trailing_slash && directory_index {
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
  !last_segment.contains(".")
}

///|
async fn resolve_history_fallback(base_dir : String) -> ServedPath {
  resolve_served_file(base_dir, "", trailing_slash=true, directory_index=true)
}

///|
async fn send_file(w : &@moonback.ResponseWriter, file_path : String) -> Unit {
  let file = @fs.open(file_path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  w.write_head(200, headers={
    "Content-Type": guess_content_type(file_path),
    "Content-Length": size.to_string(),
  })
  w.write_reader(file)
}

///|
priv struct HistoryFallbackWriter {
  inner : &@moonback.ResponseWriter
}

///|
fn HistoryFallbackWriter::new(
  inner : &@moonback.ResponseWriter,
) -> HistoryFallbackWriter {
  { inner, }
}

///|
impl @io.Writer for HistoryFallbackWriter with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  self.inner.write_once(buf, offset~, len~)
}

///|
impl @moonback.ResponseWriter for HistoryFallbackWriter with write_head(
  self,
  code,
  headers?,
) {
  if code == 404 {
    raise HistoryFallback
  }
  self.inner.write_head(code, headers?)
}

///|
impl @moonback.ResponseWriter for HistoryFallbackWriter with flush(self) {
  self.inner.flush()
}

///|
pub fn new(
  dir : String,
  directory_index? : Bool = true,
  history_fallback? : Bool = false,
) -> @moonback.Middleware {
  @moonback.Middleware((_config, next) => {
    (r, w) => {
      guard r.meth is Get else {
        next(r, w)
        return
      }

      let request_path = strip_query_and_fragment(r.path)
      let trailing_slash = has_trailing_slash(request_path)
      guard normalize_relative_path(request_path) is Some(relative_path) else {
        w.write_head(404)
        return
      }

      match
        resolve_served_file(
          dir,
          relative_path,
          trailing_slash~,
          directory_index~,
        ) {
        Missing =>
          if history_fallback &&
            relative_path != "" &&
            is_history_fallback_candidate(relative_path) {
            match resolve_history_fallback(dir) {
              Missing => next(r, w)
              Forbidden => w.write_head(403)
              Found(file_path) =>
                next(r, HistoryFallbackWriter::new(w)) catch {
                  HistoryFallback =>
                    send_file(w, file_path) catch {
                      @os_error.OSError(_) as err if err.is_ENOENT() =>
                        w.write_head(404)
                      @os_error.OSError(_) as err if err.is_EACCES() =>
                        w.write_head(403)
                      _ => w.write_head(500)
                    }
                  @os_error.OSError(_) as err if err.is_EACCES() =>
                    w.write_head(403)
                  err => raise err
                }
            }
          } else {
            next(r, w)
          }
        Forbidden => w.write_head(403)
        Found(file_path) =>
          send_file(w, file_path) catch {
            @os_error.OSError(_) as err if err.is_ENOENT() => next(r, w)
            @os_error.OSError(_) as err if err.is_EACCES() => w.write_head(403)
            _ => w.write_head(500)
          }
      }
    }
  })
}
