///|
/// Runtime configuration for an application instance.
pub struct Config {
  max_connections : Int? // Maximum number of concurrent connections. `None` means no limit.
  stop_timeout : Double // Grace period, in seconds, for in-flight connections during shutdown.
  trust_proxy : Bool // Whether proxy forwarding headers are trusted.
}

///|
/// Creates a configuration value for a new application.
/// `stop_timeout` defaults to `30` seconds.
/// `trust_proxy` defaults to `false`.
pub fn Config::Config(
  max_connections? : Int,
  stop_timeout? : Double = 30,
  trust_proxy? : Bool = false,
) -> Config {
  { max_connections, stop_timeout, trust_proxy }
}

///|
/// Returns the default application configuration.
pub impl Default for Config with fn default() -> Config {
  Config()
}
