///|
/// The async function signature for request handlers.
pub type Handler = async (Request, Responder) -> Unit

///|
/// The default handler that responds with `404 Not Found`.
pub let default_handler : Handler = (_, res) => res.send_void(status=404)
