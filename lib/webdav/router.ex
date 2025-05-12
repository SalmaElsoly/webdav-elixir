defmodule Webdav.Router do
  use Plug.Router
  require Logger

  plug(:match)
  plug(:dispatch)

  match "webdav/*path" do
    case conn.method do
      "GET" -> Webdav.Handlers.handle_get(conn)
      "PUT" -> Webdav.Handlers.handle_put(conn)
      "DELETE" -> Webdav.Handlers.handle_delete(conn)
      "MKCOL" -> Webdav.Handlers.handle_mkcol(conn)
      "PROPFIND" -> Webdav.Handlers.handle_propfind(conn)
      "PROPPATCH" -> Webdav.Handlers.handle_proppatch(conn)
      "LOCK" -> Webdav.Handlers.handle_lock(conn)
      "UNLOCK" -> Webdav.Handlers.handle_unlock(conn)
      "MOVE" -> Webdav.Handlers.handle_move(conn)
      "COPY" -> Webdav.Handlers.handle_copy(conn)
      _ -> send_resp(conn, 405, "Method not allowed")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
