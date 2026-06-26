///|
async fn render_html_for_test(html : Html) -> String {
  let out = StringBuilder()
  (html.f)(chunk => out.write_string(@utf8.decode_lossy(chunk)))
  out.to_string()
}

///|
async test "html raw keeps trusted markup" {
  let html = Html::raw("<strong>safe</strong>")
  @test.assert_eq(render_html_for_test(html), "<strong>safe</strong>")
}

///|
async test "html escape escapes dynamic text" {
  let html = Html::escape("Tom & <Jerry> \"' ")
  @test.assert_eq(
    render_html_for_test(html),
    "Tom &amp; &lt;Jerry&gt; &quot;&#39; ",
  )
}

///|
async test "html template interpolation escapes string and keeps html" {
  let html = Html(b => {
    let text = "<MoonBack>"
    let br = Html::raw("<br>")
    b <+ "\{text}"
    b <+ "\{br}"
  })
  @test.assert_eq(render_html_for_test(html), "&lt;MoonBack&gt;<br>")
}

///|
async test "html template writing escapes strings and keeps raw fragments" {
  let title = "Hello, <MoonBack>"
  let badge = Html::raw("<span class=\"badge\">new</span>")
  let page = Html(b => {
    b <+ "<article class=\"card\">"
    b <+ "<h1>\{title}</h1>"
    b <+ "\{badge}"
    b <+ "</article>"
  })
  @test.assert_eq(
    render_html_for_test(page),
    "<article class=\"card\"><h1>Hello, &lt;MoonBack&gt;</h1><span class=\"badge\">new</span></article>",
  )
}
