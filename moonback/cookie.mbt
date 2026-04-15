///|
fn parse_set_cookie(str : StringView) -> @http.Cookie raise {
  guard str.find("=") is Some(name_end) else {
    fail("Invalid cookie: no '=' found")
  }
  let name = str[:name_end].to_string()
  guard str[name_end + 1:].find(";") is Some(value_end) else {
    Cookie(name, str[name_end + 1:].to_string())
  }
  let value_end = name_end + 1 + value_end
  let value = str[name_end + 1:value_end].to_string()

  let mut path = None
  let mut expires_raw = None
  let mut max_age = None
  let mut domain = None
  let mut secure = false
  let mut http_only = false
  let extensions = []
  for parsed = value_end + 1 {
    let attr_end = if str[parsed:].find(";") is Some(attr_end) {
      parsed + attr_end
    } else {
      str.length()
    }

    let attr = str[parsed:attr_end].trim()
    if attr.find("=") is Some(attr_name_end) {
      let name = attr[:attr_name_end]
      let value = attr[attr_name_end + 1:]
      match name.to_lower() {
        "path" => path = Some(value.to_string())
        "expires" => expires_raw = Some(value.to_string())
        "max-age" => {
          let value = @string.parse_int64(value) catch {
            _ => fail("Invalid cookie: invalid max-age")
          }
          max_age = Some(value)
        }
        "domain" => domain = Some(value.to_string())
        _ => extensions.push(attr.to_string())
      }
    } else {
      match attr.to_lower() {
        "secure" => secure = true
        "httponly" => http_only = true
        _ => extensions.push(attr.to_string())
      }
    }

    if attr_end == str.length() {
      break
    } else {
      continue attr_end + 1
    }
  }
  Cookie(
    name,
    value,
    path?,
    expires_raw?,
    max_age?,
    domain?,
    secure~,
    http_only~,
    extensions~,
  )
}

///|
fn cookie_to_header_value(cookie : @http.Cookie) -> String {
  let buf = StringBuilder::new()
  buf.write_string(cookie.name)
  buf.write_string("=")
  buf.write_string(cookie.value)
  if cookie.path is Some(path) {
    buf.write_string("; Path=")
    buf.write_string(path)
  }
  if cookie.expires_raw is Some(expires_raw) {
    buf.write_string("; Expires=")
    buf.write_string(expires_raw)
  }
  if cookie.max_age is Some(max_age) {
    buf.write_string("; Max-Age=")
    buf.write_string(max_age.to_string())
  }
  if cookie.domain is Some(domain) {
    buf.write_string("; Domain=")
    buf.write_string(domain)
  }
  if cookie.secure {
    buf.write_string("; Secure")
  }
  if cookie.http_only {
    buf.write_string("; HttpOnly")
  }
  for ext in cookie.extensions {
    buf.write_string("; ")
    buf.write_string(ext)
  }
  buf.to_string()
}

///|
fn parse_cookie(str : StringView) -> Map[String, String] {
  let cookies = {}
  for parsed = 0 {
    let pair_end = if str[parsed:].find(";") is Some(pair_end) {
      parsed + pair_end
    } else {
      str.length()
    }
    let pair = str[parsed:pair_end].trim()
    if pair.find("=") is Some(name_end) {
      let name = pair[:name_end].trim()
      if !name.is_empty() {
        cookies[name.to_string()] = pair[name_end + 1:].trim().to_string()
      }
    }

    if pair_end == str.length() {
      break
    } else {
      continue pair_end + 1
    }
  }
  cookies
}
