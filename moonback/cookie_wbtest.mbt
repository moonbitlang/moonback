///|
test "parse cookie basic pairs" {
  let cookies = parse_cookie("session=abc123; theme=dark")
  assert_eq(cookies.length(), 2)
  assert_eq(cookies.get("session"), Some("abc123"))
  assert_eq(cookies.get("theme"), Some("dark"))
}

///|
test "parse cookie trims whitespace and keeps empty values" {
  let cookies = parse_cookie(" session = abc123 ; theme= dark ; empty= ")
  assert_eq(cookies.length(), 3)
  assert_eq(cookies.get("session"), Some("abc123"))
  assert_eq(cookies.get("theme"), Some("dark"))
  assert_eq(cookies.get("empty"), Some(""))
}

///|
test "parse cookie skips invalid segments and empty names" {
  let cookies = parse_cookie("session=abc123; invalid; =blank; theme=dark; ;")
  assert_eq(cookies.length(), 2)
  assert_eq(cookies.get("session"), Some("abc123"))
  assert_eq(cookies.get("theme"), Some("dark"))
}

///|
test "parse cookie keeps value suffix and latest duplicate" {
  let cookies = parse_cookie("token=part=rest; token=override")
  assert_eq(cookies.length(), 1)
  assert_eq(cookies.get("token"), Some("override"))
}
