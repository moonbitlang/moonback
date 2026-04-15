///|
async fn serve_index(
  _req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let w = res.respond(status=200, headers={
    "Content-Type": "text/html; charset=utf-8",
  })
  w.write(
    (
      #|<!DOCTYPE html>
      #|<html lang="en">
      #|  <head>
      #|    <meta charset="utf-8" />
      #|    <meta name="viewport" content="width=device-width, initial-scale=1" />
      #|    <title>moonback websocket echo</title>
      #|    <style>
      #|      :root {
      #|        color-scheme: light;
      #|        font-family: ui-monospace, "SFMono-Regular", Menlo, monospace;
      #|      }
      #|      body {
      #|        margin: 0;
      #|        min-height: 100vh;
      #|        display: grid;
      #|        place-items: center;
      #|        background: linear-gradient(135deg, #f4f1ea, #dce8f5);
      #|      }
      #|      main {
      #|        width: min(720px, calc(100vw - 32px));
      #|        padding: 24px;
      #|        border-radius: 20px;
      #|        background: rgba(255, 255, 255, 0.88);
      #|        box-shadow: 0 20px 60px rgba(30, 40, 60, 0.18);
      #|      }
      #|      h1 {
      #|        margin-top: 0;
      #|      }
      #|      form {
      #|        display: flex;
      #|        gap: 12px;
      #|        margin: 16px 0;
      #|      }
      #|      input {
      #|        flex: 1;
      #|      }
      #|      input, button {
      #|        border: 1px solid #94a3b8;
      #|        border-radius: 12px;
      #|        padding: 12px 14px;
      #|        font: inherit;
      #|      }
      #|      button {
      #|        background: #1d4ed8;
      #|        color: white;
      #|        cursor: pointer;
      #|      }
      #|      pre {
      #|        min-height: 240px;
      #|        margin: 0;
      #|        padding: 16px;
      #|        border-radius: 16px;
      #|        background: #0f172a;
      #|        color: #dbeafe;
      #|        overflow: auto;
      #|      }
      #|    </style>
      #|  </head>
      #|  <body>
      #|    <main>
      #|      <h1>moonback websocket echo</h1>
      #|      <p>Open this page in a browser, send a message, and the server will echo it back.</p>
      #|      <form id="form">
      #|        <input id="message" value="hello websocket" />
      #|        <button type="submit">Send</button>
      #|      </form>
      #|      <pre id="log"></pre>
      #|    </main>
      #|    <script>
      #|      const log = document.getElementById("log");
      #|      const form = document.getElementById("form");
      #|      const input = document.getElementById("message");
      #|      const protocol = location.protocol === "https:" ? "wss" : "ws";
      #|      const ws = new WebSocket(`${protocol}://${location.host}/ws`);
      #|
      #|      const append = (line) => {
      #|        log.textContent += `${line}\n`;
      #|        log.scrollTop = log.scrollHeight;
      #|      };
      #|
      #|      ws.addEventListener("open", () => append("connected"));
      #|      ws.addEventListener("message", (event) => append(`echo: ${event.data}`));
      #|      ws.addEventListener("close", () => append("closed"));
      #|      ws.addEventListener("error", () => append("socket error"));
      #|
      #|      form.addEventListener("submit", (event) => {
      #|        event.preventDefault();
      #|        ws.send(input.value);
      #|        append(`send: ${input.value}`);
      #|        input.select();
      #|      });
      #|    </script>
      #|  </body>
      #|</html>
    ),
  )
}

///|
async fn serve_websocket(
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let ws = res.upgrade(req)
  let client_ip = req.ip().unwrap_or("unknown")
  println("websocket connected from \{client_ip}")
  defer ws.close()
  try {
    for ;; {
      let msg = ws.recv()
      match msg.kind {
        Text => {
          let text = msg.read_all().text()
          println("recv text from \{client_ip}: \{text}")
          ws.send_text("echo: \{text}")
        }
        Binary => {
          let data = msg.read_all().binary()
          println("recv binary from \{client_ip}: \{data.length()} bytes")
          ws.send_binary(data)
        }
      }
    }
  } catch {
    @websocket.ConnectionClosed(code, reason) =>
      println(
        "websocket closed from \{client_ip}: \{@debug.to_string(code)}, reason=\{@debug.to_string(reason)}",
      )
    err => println("websocket error from \{client_ip}: \{err}")
  }
}

///|
async fn main {
  let app = @moonback.App(ctx => {
    ctx.get("/", serve_index)
    ctx.get("/ws", serve_websocket)
  })
  defer app.close()
  let server = @moonback.listen(port=3000)
  println("HTTP page:  http://127.0.0.1:3000/")
  println("WebSocket:  ws://127.0.0.1:3000/ws")
  app.serve(server)
}
