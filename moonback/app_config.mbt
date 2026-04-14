///|
pub(all) struct Config {
  max_connections : Int?
  trust_proxy : Bool
}

///|
pub impl Default for Config with default() -> Config {
  { max_connections: None, trust_proxy: false }
}
