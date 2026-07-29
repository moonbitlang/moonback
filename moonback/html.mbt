///|
/// An HTML fragment that can stream UTF-8 bytes asynchronously.
///
/// `Html` separates trusted markup from dynamic text. Raw fragments are written
/// unchanged, while `String` values written through template interpolation are
/// HTML-escaped.
///
/// # Example
/// ```mbt check
/// test {
///   let title = "Hello, <MoonBack>"
///   let badge = @moonback.Html::raw("<span class=\"badge\">new</span>")
///   let _card = @moonback.Html(b => {
///     b <+ "<article class=\"card\">"
///     b <+ "<h1>\{title}</h1>"
///     b <+ "\{badge}"
///     b <+ "</article>"
///   })
/// }
/// ```
#valtype
struct Html {
  f : async (async (Bytes) -> Unit) -> Unit
}

///|
/// A value that knows how to write itself into an `HtmlBuilder`.
///
/// Implement this trait for types that should be usable in HTML template
/// interpolation, for example `b <+ "<p>\{value}</p>"`.
pub trait WriteToHtmlBuilder {
  /// Writes this value into an `HtmlBuilder`.
  async fn write_to(Self, HtmlBuilder) -> Unit
}

///|
/// A streaming builder used by `Html`.
///
/// Literal parts of a template are written as trusted markup. Interpolated
/// values go through `WriteToHtmlBuilder`; the built-in `String`
/// implementation escapes HTML-sensitive characters.
#valtype
struct HtmlBuilder {
  k : async (Bytes) -> Unit
}

///|
/// Creates an HTML fragment from trusted raw markup.
///
/// Use this only for markup you already trust. For dynamic text, use
/// `Html::escape` or template interpolation with a `String`.
///
/// # Example
/// ```mbt check
/// test {
///   let _html = @moonback.Html::raw("<strong>safe</strong>")
/// }
/// ```
pub fn Html::raw(raw : String) -> Html {
  { f: k => k(@utf8.encode(raw)) }
}

///|
/// Creates an HTML fragment by escaping a plain text string.
///
/// # Example
/// ```mbt check
/// test {
///   let _html = @moonback.Html::escape("Tom & <Jerry>")
/// }
/// ```
pub fn Html::escape(str : String) -> Html {
  Html::raw(html_escape(str))
}

///|
/// Creates an HTML fragment from trusted UTF-8 bytes.
///
/// The bytes are written unchanged. The caller is responsible for ensuring that
/// they contain valid UTF-8 and trusted markup.
pub fn Html::raw_utf8_chunk(chunk : Bytes) -> Html {
  { f: k => k(chunk) }
}

///|
/// Builds an HTML fragment with an `HtmlBuilder`.
///
/// This is the main entry point for template writing. Static template text is
/// treated as trusted markup. Interpolated `String` values are escaped, while
/// interpolated `Html` fragments are written as-is.
///
/// # Example
/// ```mbt check
/// test {
///   let title = "Hello, <MoonBack>"
///   let badge = @moonback.Html::raw("<span class=\"badge\">new</span>")
///   let _card = @moonback.Html(b => {
///     b <+ "<article class=\"card\">"
///     b <+ "<h1>\{title}</h1>"
///     b <+ "\{badge}"
///     b <+ "</article>"
///   })
/// }
/// ```
pub fn Html::Html(f : async (HtmlBuilder) -> Unit) -> Html {
  { f: k => f({ k, }) }
}

///|
/// Writes trusted text to the output without escaping.
///
/// Prefer template interpolation for dynamic values. `write_string` is the
/// low-level primitive used for already-escaped strings and trusted literal
/// markup.
pub async fn HtmlBuilder::write_string(
  self : HtmlBuilder,
  str : String,
) -> Unit {
  (self.k)(@utf8.encode(str))
}

///|
/// Writes an interpolated template value.
///
/// This method is used by MoonBit template writing. `String` values are escaped.
/// `Html` values are written unchanged.
///
/// # Example
/// ```mbt check
/// test {
///   let _page = @moonback.Html(b => {
///     let str = "<MoonBack>"
///     let br = @moonback.Html::raw("<br>")
///     b <+ "\{str}"
///     b <+ "\{br}"
///   })
/// }
/// ```
pub async fn[T : WriteToHtmlBuilder] HtmlBuilder::write_string_interpolation(
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
pub extend Html with WriteToHtmlBuilder::{write_to}

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
