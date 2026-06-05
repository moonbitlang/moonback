///|
pub suberror DependencyError {
  /// Raised when a required dependency is missing.
  MissingDependency(name~ : String)
  /// Raised when a dependency is provided more than once.
  DuplicateDependency(name~ : String)
}

///|
fn[T] AppInst::provide_dependency(
  self : AppInst,
  key : TypedKey[T],
  value : T,
) -> Unit raise DependencyError {
  let name = key.name()
  match self.dependencies.get(key.val) {
    Some(_) => raise DuplicateDependency(name~)
    None => self.dependencies = self.dependencies.add(key.val, (key.box)(value))
  }
}

///|
fn[T] AppInst::resolve_dependency(self : AppInst, key : TypedKey[T]) -> T? {
  match self.dependencies.get(key.val) {
    None => None
    Some(value) => (key.unbox)(value)
  }
}

///|
fn[T] AppInst::require_dependency(
  self : AppInst,
  key : TypedKey[T],
) -> T raise DependencyError {
  match self.resolve_dependency(key) {
    Some(value) => value
    None => {
      let name = key.name()
      raise MissingDependency(name~)
    }
  }
}

///|
/// Provides an app-scoped dependency during module initialization.
pub fn[T] ModuleContext::provide(
  self : ModuleContext,
  key : TypedKey[T],
  value : T,
) -> Unit raise DependencyError {
  self.inst.provide_dependency(key, value)
}

///|
/// Resolves an app-scoped dependency during module initialization.
pub fn[T] ModuleContext::resolve(self : ModuleContext, key : TypedKey[T]) -> T? {
  self.inst.resolve_dependency(key)
}

///|
/// Requires an app-scoped dependency during module initialization.
pub fn[T] ModuleContext::require(
  self : ModuleContext,
  key : TypedKey[T],
) -> T raise DependencyError {
  self.inst.require_dependency(key)
}
