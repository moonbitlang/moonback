///|
/// Runtime configuration for an application instance.
pub struct Config {
  max_connections : Int? // Maximum number of concurrent connections. `None` means no limit.
  stop_timeout : Double // Grace period, in seconds, for in-flight connections during shutdown.
  trust_proxy : Bool // Whether proxy forwarding headers are trusted.
  priv custom : @immut/sorted_map.SortedMap[Int, TypedBox] // Custom configuration values, indexed by integer keys.
}

///|
struct CustomConfigEntry {
  key : Int
  value : TypedBox
}

///|
pub fn[T] Config::custom(key : TypedKey[T], value : T) -> CustomConfigEntry {
  { key: key.val, value: (key.box)(value) }
}

///|
/// Creates a configuration value for a new application.
/// `stop_timeout` defaults to `30` seconds.
/// `trust_proxy` defaults to `false`.
pub fn Config::Config(
  max_connections? : Int,
  stop_timeout? : Double = 30,
  trust_proxy? : Bool = false,
  custom? : ArrayView[CustomConfigEntry],
) -> Config {
  {
    max_connections,
    stop_timeout,
    trust_proxy,
    custom: match custom {
      None => @immut/sorted_map.SortedMap::new()
      Some(entries) =>
        @immut/sorted_map.SortedMap::from_array(
          entries.map(it => (it.key, it.value)),
        )
    },
  }
}

///|
pub fn[T] Config::get_custom(self : Config, key : TypedKey[T]) -> T? {
  match self.custom.get(key.val) {
    None => None
    Some(boxed) => (key.unbox)(boxed)
  }
}

///|
/// Returns the default application configuration.
pub impl Default for Config with fn default() -> Config {
  Config()
}
