///|
pub(open) trait Disposable {
  async dispose(Self) -> Unit
}
