///|
#valtype
struct Html {
  f : async (async (Bytes) -> Unit) -> Unit
}

///|
pub trait WriteToHtmlBuilder {
  async fn write_to(Self, HtmlBuilder) -> Unit
}

///|
#valtype
struct HtmlBuilder {
  k : async (Bytes) -> Unit
}

///|
pub fn Html::raw(raw : String) -> Html {
  { f: k => k(@utf8.encode(raw)) }
}

///|
pub fn Html::escape(str : String) -> Html {
  Html::raw(html_escape(str))
}

///|
pub fn Html::raw_utf8_chunk(chunk : Bytes) -> Html {
  { f: k => k(chunk) }
}

///|
pub fn Html::Html(f : async (HtmlBuilder) -> Unit) -> Html {
  { f: k => f({ k, }) }
}

///|
pub async fn HtmlBuilder::write_string(
  self : HtmlBuilder,
  str : String,
) -> Unit {
  (self.k)(@utf8.encode(str))
}

///|
pub async fn[T : WriteToHtmlBuilder] HtmlBuilder::write(
  self : HtmlBuilder,
  value : T,
) -> Unit {
  value.write_to(self)
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
  (self.f)(raw => (builder.k)(raw))
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
