///|
pub struct Headers {
  priv raw : Map[String, String]
  priv key : Map[String, String]

  fn new(raw? : Map[String, String]) -> Headers
}

///|
pub fn Headers::new(raw? : Map[String, String] = {}) -> Headers {
  let key_map = {}
  for key in raw.keys() {
    key_map.set(key.to_lower(), key)
  }
  { raw, key: key_map }
}

///|
pub fn Headers::get(self : Headers, key : String) -> String? {
  match self.key.get(key.to_lower()) {
    None => None
    Some(original_key) => self.raw.get(original_key)
  }
}

///|
pub fn Headers::get_multi(self : Headers, key : String) -> Array[StringView] {
  match self.get(key) {
    None => []
    Some(value) => {
      let values : Array[StringView] = []
      for part in value.split(",") {
        values.push(part.trim())
      }
      values
    }
  }
}

///|
pub fn Headers::set(self : Headers, key : String, value : String) -> Unit {
  let normalized_key = key.to_lower()
  match self.key.get(normalized_key) {
    Some(original_key) =>
      if original_key != key {
        self.raw.remove(original_key)
      }
    None => ()
  }
  self.key.set(normalized_key, key)
  self.raw.set(key, value)
}

///|
pub fn Headers::append(self : Headers, key : String, value : String) -> Unit {
  let normalized_key = key.to_lower()
  match self.key.get(normalized_key) {
    Some(original_key) => {
      let next_value = match self.raw.get(original_key) {
        Some(current_value) => "\{current_value}, \{value}"
        None => value
      }
      self.raw.set(original_key, next_value)
    }
    None => self.set(key, value)
  }
}

///|
pub fn Headers::remove(self : Headers, key : String) -> Unit {
  let normalized_key = key.to_lower()
  match self.key.get(normalized_key) {
    Some(original_key) => {
      self.key.remove(normalized_key)
      self.raw.remove(original_key)
    }
    None => ()
  }
}

///|
pub fn Headers::repr(self : Headers) -> Map[String, String] {
  self.raw
}
