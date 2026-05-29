///|
test "parse query params basic pairs" {
  let query = parse_query_params(Some("page=1&q=moonbit"))
  @test.assert_eq(query.get("page"), Some("1"))
  @test.assert_eq(query.get("q"), Some("moonbit"))
  @test.assert_eq(query.has("missing"), false)
}

///|
test "parse query params keeps repeated values in order" {
  let query = parse_query_params(Some("tag=a&tag=b&tag=c"))
  @test.assert_eq(query.get("tag"), Some("a"))
  @test.assert_eq(query.get_all("tag"), ["a", "b", "c"])
}

///|
test "parse query params handles empty values and valueless names" {
  let query = parse_query_params(Some("a=&b&=blank&&c=3&"))
  @test.assert_eq(query.get("a"), Some(""))
  @test.assert_eq(query.get("b"), Some(""))
  @test.assert_eq(query.get(""), Some("blank"))
  @test.assert_eq(query.get("c"), Some("3"))
  @test.assert_eq(query.iter().to_array(), [
    ("a", ""),
    ("b", ""),
    ("", "blank"),
    ("c", "3"),
  ])
}

///|
test "parse query params decodes percent encoding and plus as space" {
  let query = parse_query_params(
    Some("q=hello+moon%21&utf8=%E4%B8%AD%E6%96%87&raw=中文"),
  )
  @test.assert_eq(query.get("q"), Some("hello moon!"))
  @test.assert_eq(query.get("utf8"), Some("中文"))
  @test.assert_eq(query.get("raw"), Some("中文"))
}

///|
test "parse query params distinguishes plus space and encoded plus" {
  let query = parse_query_params(
    Some(
      "plus=a+b&percent_space=a%20b&raw_space=a b&literal_plus=a%2Bb&a+b=key-plus&%2B=encoded-key",
    ),
  )
  @test.assert_eq(query.get("plus"), Some("a b"))
  @test.assert_eq(query.get("percent_space"), Some("a b"))
  @test.assert_eq(query.get("raw_space"), Some("a b"))
  @test.assert_eq(query.get("literal_plus"), Some("a+b"))
  @test.assert_eq(query.get("a b"), Some("key-plus"))
  @test.assert_eq(query.get("+"), Some("encoded-key"))
}

///|
test "parse query params preserves invalid percent escapes literally" {
  let query = parse_query_params(Some("x=%zz%2&y=100%25"))
  @test.assert_eq(query.get("x"), Some("%zz%2"))
  @test.assert_eq(query.get("y"), Some("100%"))
}

///|
test "parse query params handles absent and empty raw search" {
  @test.assert_eq(parse_query_params(None).iter().to_array(), [])
  @test.assert_eq(parse_query_params(Some("")).iter().to_array(), [])
}
