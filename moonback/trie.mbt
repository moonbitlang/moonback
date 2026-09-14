///|
/// Trie node for path-based routing
/// Uses SparseArray128 indexed by first character for O(1) lookup
/// T is the payload type stored at leaf nodes
priv struct Trie[T] {
  segment : StringView // Path segment (actual path for static nodes, param name for param nodes)
  children : FixedArray[Array[Trie[T]]?] // Child nodes indexed by first character
  mut param_child : Trie[T]? // Parameter child node :id
  mut catch_all_child : Trie[T]? // Catch-all child node *rest
  mut payload : T?
}

///|
fn[T] Trie::new(segment : StringView) -> Trie[T] {
  {
    segment,
    children: FixedArray::make(128, None),
    param_child: None,
    catch_all_child: None,
    payload: None,
  }
}

///|
/// Create a new root trie node
fn[T] Trie::root() -> Trie[T] {
  Trie::new("")
}

///|
/// Find or create a static child node
fn[T] Trie::find_or_create_static_child(
  self : Trie[T],
  segment : StringView,
) -> Trie[T] {
  if segment.length() == 0 {
    abort("segment cannot be empty")
  }

  // Use first character as index
  let first_char = segment.code_unit_at(0).to_int()

  // Find existing static child node
  match self.children[first_char] {
    Some(nodes) => {
      // Find exact segment match among nodes with same first character
      for node in nodes {
        if node.segment == segment {
          return node
        }
      }
      // Not found, create new node
      let child = Trie::new(segment)
      nodes.push(child)
      child
    }
    None => {
      // No nodes under this first character, create new array
      let child = Trie::new(segment)
      let nodes : Array[Trie[T]] = [child]
      self.children[first_char] = Some(nodes)
      child
    }
  }
}

///|
/// Find or create a param child node
fn[T] Trie::find_or_create_param_child(
  self : Trie[T],
  param_name : StringView,
) -> Trie[T] {
  match self.param_child {
    Some(child) =>
      // If param name differs, we allow it but use the existing node
      // The new param name will be used during routing
      return child
    None => {
      let child = Trie::new(param_name)
      self.param_child = Some(child)
      child
    }
  }
}

///|
/// Find or create a catch-all child node
fn[T] Trie::find_or_create_catch_all_child(
  self : Trie[T],
  param_name : StringView,
) -> Trie[T] {
  match self.catch_all_child {
    Some(child) => child
    None => {
      let child = Trie::new(param_name)
      self.catch_all_child = Some(child)
      child
    }
  }
}

///|
/// Parse path into segments
fn parse_path(path : StringView) -> Array[StringView] {
  let segments : Array[StringView] = []
  let len = path.length()
  let mut i = 0

  // Skip leading slash
  if len > 0 && path.code_unit_at(0).to_int() == '/'.to_int() {
    i = 1
  }
  let mut start = i
  while i < len {
    if path.code_unit_at(i).to_int() == '/'.to_int() {
      if i > start {
        segments.push(path[start:i])
      }
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }

  // Add last segment
  if i > start {
    segments.push(path[start:i])
  }
  segments
}

///|
/// Insert a payload at the given path
/// Supports :param for path parameters and *rest for catch-all
fn[T] Trie::insert(self : Trie[T], path : StringView, payload : T) -> Unit {
  let segments = parse_path(path)
  let mut current = self
  for segment in segments {
    if segment.length() > 0 && segment.code_unit_at(0).to_int() == '*'.to_int() {
      // Catch-all parameter *rest
      let param_name = if segment.length() > 1 { segment[1:] } else { "rest" }
      current = current.find_or_create_catch_all_child(param_name)
      // Catch-all must be the last segment
      break
    } else if segment.length() > 0 &&
      segment.code_unit_at(0).to_int() == ':'.to_int() {
      // Parameter :id
      let param_name = segment[1:]
      current = current.find_or_create_param_child(param_name)
    } else {
      // Static segment
      current = current.find_or_create_static_child(segment)
    }
  }
  current.payload = Some(payload)
}

///|
/// Match result from trie search
priv struct MatchResult[T] {
  payload : T
  params : Map[StringView, StringView]
}

///|
/// Search for a path in the trie
/// Returns the payload and extracted parameters if found
fn[T] Trie::search(self : Trie[T], path : StringView) -> MatchResult[T]? {
  let segments = parse_path(path)
  let params : Map[StringView, StringView] = Map([])
  match self.search_recursive(segments, params) {
    Some(node) =>
      match node.payload {
        Some(payload) => Some({ payload, params, })
        None => None
      }
    None => None
  }
}

///|
/// Recursive search helper
/// Returns the matched node if found
fn[T] Trie::search_recursive(
  self : Trie[T],
  segments : ArrayView[StringView],
  params : Map[StringView, StringView],
) -> Trie[T]? {
  if segments.length() == 0 {
    // Reached end of path
    if self.payload is Some(_) {
      return Some(self)
    }
    return None
  }
  let segment = segments[0]
  let remaining = segments[1:]

  // 1. Try static match first (highest priority)
  if segment.length() > 0 {
    let first_char = segment.code_unit_at(0).to_int()
    match self.children[first_char] {
      Some(nodes) =>
        for node in nodes {
          if node.segment == segment {
            match node.search_recursive(remaining, params) {
              Some(result) => return Some(result)
              None => ()
            }
          }
        }
      None => ()
    }
  }

  // 2. Try parameter match :id
  match self.param_child {
    Some(child) => {
      // Save parameter value
      let old_value = params.get(child.segment)
      params.set(child.segment, segment)
      match child.search_recursive(remaining, params) {
        Some(result) => return Some(result)
        None =>
          // Backtrack: restore parameter
          match old_value {
            Some(v) => params.set(child.segment, v)
            None => params.remove(child.segment) |> ignore
          }
      }
    }
    None => ()
  }

  // 3. Try catch-all match *rest (lowest priority)
  match self.catch_all_child {
    Some(child) => {
      // Catch-all captures all remaining path segments
      let rest_path = segments
        .iter()
        .intersperse("/")
        .fold(init="", fn(acc, s) { acc + s.to_owned() })
      params.set(child.segment, rest_path)
      if child.payload is Some(_) {
        return Some(child)
      }
    }
    None => ()
  }
  None
}
