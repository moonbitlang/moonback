///|
test "headers are case insensitive for get set append and remove" {
  let headers = Headers::new(raw={ "Content-Type": "text/plain" })

  assert_eq(headers.get("content-type"), Some("text/plain"))
  assert_eq(headers.get_multi("CONTENT-TYPE").map(v => v.to_string()), [
    "text/plain",
  ])

  headers.set("x-request-id", "abc")
  assert_eq(headers.get("X-Request-Id"), Some("abc"))
  assert_eq(headers.repr().get("x-request-id"), Some("abc"))

  headers.append("X-REQUEST-ID", "def")
  assert_eq(headers.get("x-request-id"), Some("abc, def"))
  assert_eq(headers.get_multi("x-request-id").map(v => v.to_string()), [
    "abc", "def",
  ])

  headers.remove("X-Request-ID")
  assert_true(headers.get("x-request-id") is None)
  assert_true(headers.repr().get("x-request-id") is None)
}

///|
test "headers set replaces existing key casing" {
  let headers = Headers::new(raw={ "Content-Type": "text/plain" })

  headers.set("content-type", "application/json")

  assert_true(headers.repr().get("Content-Type") is None)
  assert_eq(headers.repr().get("content-type"), Some("application/json"))
  assert_eq(headers.get("CONTENT-TYPE"), Some("application/json"))
}

///|
test "headers get_multi trims comma separated values" {
  let headers = Headers::new(raw={
    "Accept": "application/json, text/plain ,  text/html  ",
  })

  assert_eq(headers.get_multi("accept").map(v => v.to_string()), [
    "application/json", "text/plain", "text/html",
  ])
}
