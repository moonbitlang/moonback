///|
priv suberror StopResponding

///|
priv suberror PrivTypedKey {
  Cookies(Map[String, String])
  QueryParams(QueryParams)
}

///|
fn join_host_port(host : String, port : UInt16) -> String {
  if host.contains_char(':') {
    "[\{host}]:\{port}"
  } else {
    "\{host}:\{port}"
  }
}

///|
fn extract_host(host_port : String) -> StringView {
  match host_port.rev_split_once(":") {
    Some((host, _)) => host
    None => host_port
  }
}

///|
fn status_to_reason_phrase(code : Int) -> String {
  match code {
    100 => "Continue"
    101 => "Switching Protocols"
    102 => "Processing"
    103 => "Early Hints"
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    203 => "Non-Authoritative Information"
    204 => "No Content"
    205 => "Reset Content"
    206 => "Partial Content"
    207 => "Multi-Status"
    208 => "Already Reported"
    226 => "IM Used"
    300 => "Multiple Choices"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    305 => "Use Proxy"
    306 => "Unused"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    402 => "Payment Required"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    406 => "Not Acceptable"
    407 => "Proxy Authentication Required"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Content Too Large"
    414 => "URI Too Long"
    415 => "Unsupported Media Type"
    416 => "Range Not Satisfiable"
    417 => "Expectation Failed"
    418 => "I'm a teapot"
    421 => "Misdirected Request"
    422 => "Unprocessable Content"
    423 => "Locked"
    424 => "Failed Dependency"
    425 => "Too Early"
    426 => "Upgrade Required"
    428 => "Precondition Required"
    429 => "Too Many Requests"
    431 => "Request Header Fields Too Large"
    451 => "Unavailable For Legal Reasons"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    505 => "HTTP Version Not Supported"
    506 => "Variant Also Negotiates"
    507 => "Insufficient Storage"
    508 => "Loop Detected"
    510 => "Not Extended"
    511 => "Network Authentication Required"
    _ => "Unknown"
  }
}

///|
fn iter_optional_to_headers(headers : &ToHeaders?) -> Iter[(String, String)] {
  match headers {
    None => Iter::empty()
    Some(h) => h.to_headers().iter()
  }
}

///|
fn split_path_search(path_search : String) -> (StringView, StringView?) {
  match path_search.split_once("?") {
    Some((path, search)) => (path, Some(search))
    None => (path_search, None)
  }
}
