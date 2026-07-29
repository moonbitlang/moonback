///|
/// Decoded query parameters from a request URL.
///
/// Query decoding follows `application/x-www-form-urlencoded`: `+` decodes to
/// a space, `%20` also decodes to a space, and a literal plus sign must be
/// encoded as `%2B`.
pub struct QueryParams {
  priv values : Map[String, ReadOnlyArray[String]]
  priv entries : Array[(String, String)]
}

///|
fn hex_value(ch : UInt16) -> Int? {
  let code = ch.to_int()
  if code >= '0'.to_int() && code <= '9'.to_int() {
    Some(code - '0'.to_int())
  } else if code >= 'A'.to_int() && code <= 'F'.to_int() {
    Some(code - 'A'.to_int() + 10)
  } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
    Some(code - 'a'.to_int() + 10)
  } else {
    None
  }
}

///|
fn x_www_form_url_decode(input : StringView) -> String {
  let out : Array[Byte] = []
  let len = input.length()
  let mut i = 0
  while i < len {
    let ch = input.code_unit_at(i)
    if ch.to_int() == '+'.to_int() {
      out.push(' '.to_int().to_byte())
      i += 1
    } else if ch.to_int() == '%'.to_int() && i + 2 < len {
      match
        (
          hex_value(input.code_unit_at(i + 1)),
          hex_value(input.code_unit_at(i + 2)),
        ) {
        (Some(hi), Some(lo)) => {
          out.push((hi * 16 + lo).to_byte())
          i += 3
        }
        _ => {
          out.push(ch.to_byte())
          i += 1
        }
      }
    } else {
      let next = if i + 1 < len &&
        input.code_unit_at(i).is_leading_surrogate() &&
        input.code_unit_at(i + 1).is_trailing_surrogate() {
        i + 2
      } else {
        i + 1
      }
      out.push_iter(@utf8.encode(input[i:next]).iter())
      i = next
    }
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
fn parse_query_pair(pair : StringView) -> (String, String) {
  match pair.split_once("=") {
    Some((name, value)) =>
      (x_www_form_url_decode(name), x_www_form_url_decode(value))
    None => (x_www_form_url_decode(pair), "")
  }
}

///|
fn parse_query_params(search : StringView?) -> QueryParams {
  let entries : Array[(String, String)] = []
  guard search is Some(search) else { return { values: {}, entries } }
  let values : Map[String, Array[String]] = Map([])
  for parsed = 0 {
    let pair_end = if search[parsed:].find("&") is Some(pair_end) {
      parsed + pair_end
    } else {
      search.length()
    }
    let pair = search[parsed:pair_end]
    if !pair.is_empty() {
      let (name, value) = parse_query_pair(pair)
      entries.push((name, value))
      match values.get(name) {
        Some(items) => items.push(value)
        None => values[name] = [value]
      }
    }

    if pair_end == search.length() {
      break
    } else {
      continue pair_end + 1
    }
  }
  { values: values.map((_k, v) => ReadOnlyArray::from_array(v)), entries }
}

///|
/// Returns the first value for a query parameter name, if present.
pub fn QueryParams::get(self : QueryParams, name : StringView) -> String? {
  match self.values.get_from_string(name) {
    Some(values) => values.get(0)
    None => None
  }
}

///|
/// Returns all values for a query parameter name in request order.
pub fn QueryParams::get_all(
  self : QueryParams,
  name : StringView,
) -> ReadOnlyArray[String] {
  match self.values.get_from_string(name) {
    Some(values) => values
    None => []
  }
}

///|
/// Returns whether a query parameter name is present.
pub fn QueryParams::has(self : QueryParams, name : StringView) -> Bool {
  self.values.get_from_string(name) is Some(_)
}

///|
/// Iterates over decoded query parameter pairs in request order.
pub fn QueryParams::iter(self : QueryParams) -> Iter[(String, String)] {
  self.entries.iter()
}
