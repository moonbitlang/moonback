///|
/// Test basic static route matching
test "static route - single segment" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "users_handler")
  let result = trie.search("/users")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "users_handler")
  @test.assert_eq(r.params.length(), 0)
}

///|
test "static route - multiple segments" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/api/v1/users", "api_users")
  let result = trie.search("/api/v1/users")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "api_users")
}

///|
test "static route - not found" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "users_handler")
  assert_true(trie.search("/posts") is None)
  assert_true(trie.search("/users/123") is None)
  assert_true(trie.search("/user") is None)
}

///|
test "static route - root path" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/", "root_handler")
  let result = trie.search("/")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "root_handler")
}

///|
test "static route - multiple routes same prefix" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "users_list")
  trie.insert("/users/new", "users_new")
  trie.insert("/users/edit", "users_edit")
  guard trie.search("/users") is Some(r1) else { fail("expected Some") }
  guard trie.search("/users/new") is Some(r2) else { fail("expected Some") }
  guard trie.search("/users/edit") is Some(r3) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "users_list")
  @test.assert_eq(r2.payload, "users_new")
  @test.assert_eq(r3.payload, "users_edit")
}

///|
/// Test parameter route matching
test "param route - single param" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users/:id", "user_detail")
  let result = trie.search("/users/123")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "user_detail")
  @test.assert_eq(r.params.get("id"), Some("123"))
}

///|
test "param route - multiple params" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users/:userId/posts/:postId", "user_post")
  let result = trie.search("/users/42/posts/99")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "user_post")
  @test.assert_eq(r.params.get("userId"), Some("42"))
  @test.assert_eq(r.params.get("postId"), Some("99"))
}

///|
test "param route - mixed static and param" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/api/:version/users/:id/profile", "user_profile")
  let result = trie.search("/api/v2/users/abc/profile")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "user_profile")
  @test.assert_eq(r.params.get("version"), Some("v2"))
  @test.assert_eq(r.params.get("id"), Some("abc"))
}

///|
test "param route - param with special characters" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/files/:filename", "file_handler")
  let result = trie.search("/files/my-file_v2.txt")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.params.get("filename"), Some("my-file_v2.txt"))
}

///|
/// Test catch-all route matching
test "catch-all route - basic" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/static/*filepath", "static_handler")
  let result = trie.search("/static/css/style.css")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "static_handler")
  @test.assert_eq(r.params.get("filepath"), Some("css/style.css"))
}

///|
test "catch-all route - single segment" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/files/*path", "files_handler")
  let result = trie.search("/files/readme.md")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.params.get("path"), Some("readme.md"))
}

///|
test "catch-all route - deep path" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/assets/*rest", "assets_handler")
  let result = trie.search("/assets/images/icons/logo.png")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.params.get("rest"), Some("images/icons/logo.png"))
}

///|
test "catch-all route - default name" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/download/*", "download_handler")
  let result = trie.search("/download/file.zip")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.params.get("rest"), Some("file.zip"))
}

///|
/// Test route priority
test "priority - static over param" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users/new", "users_new")
  trie.insert("/users/:id", "users_show")

  // Static should match first
  guard trie.search("/users/new") is Some(r1) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "users_new")
  // Param should match other values
  guard trie.search("/users/123") is Some(r2) else { fail("expected Some") }
  @test.assert_eq(r2.payload, "users_show")
}

///|
test "priority - param over catch-all" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/files/:name", "file_by_name")
  trie.insert("/files/*path", "file_catch_all")

  // Param should match single segment
  let result1 = trie.search("/files/test.txt")
  guard result1 is Some(r1) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "file_by_name")
  @test.assert_eq(r1.params.get("name"), Some("test.txt"))

  // Catch-all should match multiple segments
  let result2 = trie.search("/files/dir/test.txt")
  guard result2 is Some(r2) else { fail("expected Some") }
  @test.assert_eq(r2.payload, "file_catch_all")
  @test.assert_eq(r2.params.get("path"), Some("dir/test.txt"))
}

///|
test "priority - static over param over catch-all" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/api/health", "health_check")
  trie.insert("/api/:resource", "resource_handler")
  trie.insert("/api/*rest", "catch_all_handler")
  guard trie.search("/api/health") is Some(r1) else { fail("expected Some") }
  guard trie.search("/api/users") is Some(r2) else { fail("expected Some") }
  guard trie.search("/api/v1/users") is Some(r3) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "health_check")
  @test.assert_eq(r2.payload, "resource_handler")
  @test.assert_eq(r3.payload, "catch_all_handler")
}

///|
/// Test edge cases
test "edge case - empty path segments" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "users")

  // Double slash should be handled
  let result = trie.search("//users")
  // Depending on implementation, this might not match
  // Our parse_path skips empty segments
  assert_true(result is Some(_))
}

///|
test "edge case - trailing slash" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "users_no_slash")
  trie.insert("/posts/", "posts_with_slash")

  // Without trailing slash
  guard trie.search("/users") is Some(r1) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "users_no_slash")
  // With trailing slash in pattern - should work since we skip empty segments
  guard trie.search("/posts") is Some(r2) else { fail("expected Some") }
  @test.assert_eq(r2.payload, "posts_with_slash")
}

///|
test "edge case - no leading slash" {
  let trie : Trie[String] = Trie::root()
  trie.insert("users/list", "users_list")
  let result = trie.search("users/list")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "users_list")
}

///|
test "edge case - same first char different segments" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "users")
  trie.insert("/user", "user")
  trie.insert("/username", "username")
  guard trie.search("/users") is Some(r1) else { fail("expected Some") }
  guard trie.search("/user") is Some(r2) else { fail("expected Some") }
  guard trie.search("/username") is Some(r3) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "users")
  @test.assert_eq(r2.payload, "user")
  @test.assert_eq(r3.payload, "username")
  assert_true(trie.search("/use") is None)
}

///|
test "edge case - overwrite payload" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/users", "first")
  trie.insert("/users", "second")

  // Second insert should overwrite
  guard trie.search("/users") is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "second")
}

///|
test "edge case - param at different positions" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/:a/b/c", "first")
  trie.insert("/a/:b/c", "second")
  trie.insert("/a/b/:c", "third")
  guard trie.search("/x/b/c") is Some(r1) else { fail("expected Some") }
  guard trie.search("/a/x/c") is Some(r2) else { fail("expected Some") }
  guard trie.search("/a/b/x") is Some(r3) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "first")
  @test.assert_eq(r2.payload, "second")
  @test.assert_eq(r3.payload, "third")
}

///|
test "edge case - numeric path segments" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/v1/api", "v1_api")
  trie.insert("/v2/api", "v2_api")
  trie.insert("/:version/api", "version_api")
  guard trie.search("/v1/api") is Some(r1) else { fail("expected Some") }
  guard trie.search("/v2/api") is Some(r2) else { fail("expected Some") }
  guard trie.search("/v3/api") is Some(r3) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "v1_api")
  @test.assert_eq(r2.payload, "v2_api")
  @test.assert_eq(r3.payload, "version_api")
}

///|
test "edge case - backtracking" {
  let trie : Trie[String] = Trie::root()
  // This tests the backtracking logic
  trie.insert("/a/:x/c", "param_route")
  trie.insert("/a/b/d", "static_route")

  // Should match param_route with x=b
  let result1 = trie.search("/a/b/c")
  guard result1 is Some(r1) else { fail("expected Some") }
  @test.assert_eq(r1.payload, "param_route")
  @test.assert_eq(r1.params.get("x"), Some("b"))

  // Should match static_route
  let result2 = trie.search("/a/b/d")
  guard result2 is Some(r2) else { fail("expected Some") }
  @test.assert_eq(r2.payload, "static_route")
}

///|
test "edge case - long path" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/a/b/c/d/e/f/g/h/i/j", "long_path")
  let result = trie.search("/a/b/c/d/e/f/g/h/i/j")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "long_path")

  // Partial path should not match
  assert_true(trie.search("/a/b/c/d/e") is None)
}

///|
test "edge case - unicode segments" {
  let trie : Trie[String] = Trie::root()
  trie.insert("/hello/world", "ascii")
  let result = trie.search("/hello/world")
  guard result is Some(r) else { fail("expected Some") }
  @test.assert_eq(r.payload, "ascii")
}

///|
/// Test complex scenarios
test "complex - realistic api routes" {
  let trie : Trie[String] = Trie::root()

  // RESTful API routes
  trie.insert("/api/users", "list_users")
  trie.insert("/api/users/:id", "get_user")
  trie.insert("/api/users/:id/posts", "user_posts")
  trie.insert("/api/users/:id/posts/:postId", "user_post")
  trie.insert("/api/posts", "list_posts")
  trie.insert("/api/posts/:id", "get_post")
  trie.insert("/api/posts/:id/comments", "post_comments")
  trie.insert("/static/*filepath", "serve_static")
  guard trie.search("/api/users") is Some(r1) else { fail("expected Some") }
  guard trie.search("/api/users/42") is Some(r2) else { fail("expected Some") }
  guard trie.search("/api/users/42/posts") is Some(r3) else {
    fail("expected Some")
  }
  guard trie.search("/api/users/42/posts/7") is Some(r4) else {
    fail("expected Some")
  }
  guard trie.search("/api/posts") is Some(r5) else { fail("expected Some") }
  guard trie.search("/api/posts/99") is Some(r6) else { fail("expected Some") }
  guard trie.search("/api/posts/99/comments") is Some(r7) else {
    fail("expected Some")
  }
  guard trie.search("/static/js/app.js") is Some(r8) else {
    fail("expected Some")
  }
  @test.assert_eq(r1.payload, "list_users")
  @test.assert_eq(r2.payload, "get_user")
  @test.assert_eq(r3.payload, "user_posts")
  @test.assert_eq(r4.payload, "user_post")
  @test.assert_eq(r5.payload, "list_posts")
  @test.assert_eq(r6.payload, "get_post")
  @test.assert_eq(r7.payload, "post_comments")
  @test.assert_eq(r8.payload, "serve_static")

  // Verify params
  @test.assert_eq(r4.params.get("id"), Some("42"))
  @test.assert_eq(r4.params.get("postId"), Some("7"))
}

///|
test "static route - unicode and colliding first code units" {
  let trie : Trie[Int] = Trie::root()
  trie.insert("/a/item", 1)
  trie.insert("/á/item", 2)
  trie.insert("/中文/😀", 3)
  for (path, payload) in [("/a/item", 1), ("/á/item", 2), ("/中文/😀", 3)] {
    guard trie.search(path) is Some(result) else { fail("expected match") }
    assert_eq(result.payload, payload)
  }
  assert_true(trie.search("/中文/不存在") is None)
}

///|
test "catch all preserves normalized segments after backtracking" {
  let trie : Trie[Int] = Trie::root()
  trie.insert("/files/:id/end", 1)
  trie.insert("/files/*rest", 2)
  for path in ["/files/a/b/", "//files///a//b///", "files/a/b"] {
    guard trie.search(path) is Some(result) else { fail("expected match") }
    assert_eq(result.payload, 2)
    assert_eq(result.params.get("rest"), Some("a/b"))
    assert_eq(result.params.get("id"), None)
  }
  assert_true(trie.search("/files///") is None)
}

///|
test "catch all handles long paths and independent parameter maps" {
  let trie : Trie[Int] = Trie::root()
  trie.insert("/files/*rest", 1)
  let rest = Array::make(128, "中文😀").join("/")
  guard trie.search("/files/" + rest) is Some(first) else {
    fail("expected match")
  }
  guard trie.search("/files/other") is Some(second) else {
    fail("expected match")
  }
  assert_eq(first.params.get("rest"), Some(rest[:]))
  assert_eq(second.params.get("rest"), Some("other"))
}

///|
test "catch all normalizes every separator combination" {
  let trie : Trie[Int] = Trie::root()
  trie.insert("/files/*rest", 1)
  for leading in ["/", "//"] {
    for first in ["/", "//", "///"] {
      for second in ["/", "//", "///"] {
        for trailing in ["", "/", "///"] {
          let path = leading +
            "files" +
            first +
            "中文" +
            second +
            "😀" +
            trailing
          guard trie.search(path) is Some(result) else {
            fail("expected match")
          }
          assert_eq(result.params.get("rest"), Some("中文/😀"))
        }
      }
    }
  }
}
