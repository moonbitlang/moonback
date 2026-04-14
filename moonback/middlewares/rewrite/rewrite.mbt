///|
priv struct RewriteRule {
  pattern : String
  replacement : String
}

///|
fn split_path_suffix(path : String) -> (String, String) {
  let mut end = path.length()
  if path.find("?") is Some(index) && index < end {
    end = index
  }
  if path.find("#") is Some(index) && index < end {
    end = index
  }
  (path[:end].to_string(), path[end:].to_string())
}

///|
fn is_ascii_digit(code : Int) -> Bool {
  code >= '0'.to_int() && code <= '9'.to_int()
}

///|
fn wildcard_match(pattern : String, path : String) -> Array[String]? {
  let captures : Array[String] = []
  if wildcard_match_from(pattern, 0, path, 0, captures) {
    Some(captures)
  } else {
    None
  }
}

///|
fn wildcard_match_from(
  pattern : String,
  pattern_index : Int,
  path : String,
  path_index : Int,
  captures : Array[String],
) -> Bool {
  if pattern_index == pattern.length() {
    return path_index == path.length()
  }

  if pattern.code_unit_at(pattern_index).to_int() == '*'.to_int() {
    for end = path_index; end <= path.length(); end = end + 1 {
      captures.push(path[path_index:end].to_string())
      if wildcard_match_from(pattern, pattern_index + 1, path, end, captures) {
        return true
      }
      captures.pop() |> ignore
    }
    return false
  }

  guard path_index < path.length() else { return false }
  if pattern.code_unit_at(pattern_index) != path.code_unit_at(path_index) {
    return false
  }
  wildcard_match_from(
    pattern,
    pattern_index + 1,
    path,
    path_index + 1,
    captures,
  )
}

///|
fn render_replacement(replacement : String, captures : Array[String]) -> String {
  let rendered = StringBuilder::new()
  let mut i = 0
  while i < replacement.length() {
    let code = replacement.code_unit_at(i).to_int()
    if code == '$'.to_int() {
      let mut j = i + 1
      let mut capture_index = 0
      while j < replacement.length() {
        let digit = replacement.code_unit_at(j).to_int()
        if !is_ascii_digit(digit) {
          break
        }
        capture_index = capture_index * 10 + digit - '0'.to_int()
        j = j + 1
      }
      if j > i + 1 {
        if capture_index > 0 && capture_index <= captures.length() {
          rendered.write_string(captures[capture_index - 1])
        }
        i = j
      } else {
        rendered.write_char('$')
        i = i + 1
      }
    } else {
      rendered.write_char(code.unsafe_to_char())
      i = i + 1
    }
  }
  rendered.to_string()
}

///|
fn rewrite_path(rules : Array[RewriteRule], path : String) -> String {
  let (pathname, suffix) = split_path_suffix(path)
  for rule in rules {
    match wildcard_match(rule.pattern, pathname) {
      Some(captures) =>
        return render_replacement(rule.replacement, captures) + suffix
      None => ()
    }
  }
  path
}

///|
/// Rewrite request paths using wildcard rules.
///
/// Rules are evaluated in insertion order. Each `*` in the source pattern
/// captures a wildcard, which can be referenced in the destination pattern
/// using `$1`, `$2`, and so on.
pub fn new(rules : Map[String, String]) -> @moonback.Middleware {
  let compiled : Array[RewriteRule] = []
  rules.each((pattern, replacement) => compiled.push({ pattern, replacement }))

  @moonback.Middleware((_config, next) => {
    (r, w) => {
      let new_path = rewrite_path(compiled, r.path)
      if new_path == r.path {
        next(r, w)
      } else {
        next({ ..r, path: new_path }, w)
      }
    }
  })
}
