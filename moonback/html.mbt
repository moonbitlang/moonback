///|
#valtype
struct Html {
  raw : String
}

///|
pub trait WriteToHtmlBuilder {
  fn write_to(Self, HtmlBuilder) -> Unit
}

///|
#valtype
struct HtmlBuilder {
  buffer : StringBuilder
}

///|
pub fn Html::Html(raw~ : String) -> Html {
  { raw, }
}

///|
pub fn Html::escape(str : String) -> Html {
  Html(raw=html_escape(str))
}

///|
pub fn Html::build(f : (HtmlBuilder) -> Unit) -> Html {
  let b = HtmlBuilder()
  f(b)
  b.html()
}

///|
pub fn HtmlBuilder::HtmlBuilder() -> HtmlBuilder {
  { buffer: StringBuilder() }
}

///|
pub fn HtmlBuilder::write_string(self : HtmlBuilder, str : String) -> Unit {
  self.buffer.write_string(str)
}

///|
pub fn[T : WriteToHtmlBuilder] HtmlBuilder::write(
  self : HtmlBuilder,
  value : T,
) -> Unit {
  value.write_to(self)
}

///|
pub fn HtmlBuilder::html(self : HtmlBuilder) -> Html {
  Html(raw=self.buffer.to_string())
}

///|
pub impl WriteToHtmlBuilder for String with fn write_to(
  self : String,
  builder : HtmlBuilder,
) {
  builder.write_string(html_escape(self))
}

///|
pub impl WriteToHtmlBuilder for Html with fn write_to(
  self : Html,
  builder : HtmlBuilder,
) {
  builder.write_string(self.raw)
}

///|
fn html_escape(s : String) -> String {
  // TODO: Use lexmatch
  let b = StringBuilder()
  for ch in s {
    match ch {
      '&' => b.write_string("&amp;")
      '<' => b.write_string("&lt;")
      '>' => b.write_string("&gt;")
      '"' => b.write_string("&quot;")
      '\'' => b.write_string("&#39;")
      _ => b.write_char(ch)
    }
  }
  b.to_string()
}
