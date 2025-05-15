defmodule Webdav.Router do
  use Plug.Router
  require Logger
  import Plug.Conn

  plug(:match)
  plug(:dispatch)

  match "webdav/*path" do
    conn = put_resp_header(conn, "DAV", "1, 2")
    Logger.info([path: conn.request_path, method: conn.method, headers: conn.req_headers])

    case conn.method do
      "GET" ->
        Webdav.Handlers.handle_get(conn)

      "PUT" ->
        Webdav.Handlers.handle_put(conn)

      "DELETE" ->
        Webdav.Handlers.handle_delete(conn)

      "MKCOL" ->
        Webdav.Handlers.handle_mkcol(conn)

      "PROPFIND" ->
        Webdav.Handlers.handle_propfind(conn)

      "PROPPATCH" ->
        Webdav.Handlers.handle_proppatch(conn)

      "LOCK" ->
        Webdav.Handlers.handle_lock(conn)

      "UNLOCK" ->
        Webdav.Handlers.handle_unlock(conn)

      "MOVE" ->
        Webdav.Handlers.handle_move(conn)

      "COPY" ->
        Webdav.Handlers.handle_copy(conn)

      "OPTIONS" ->
        conn
        |> put_resp_header(
          "Allow",
          "OPTIONS, GET, PUT, DELETE, MKCOL, PROPFIND, PROPPATCH, LOCK, UNLOCK, MOVE, COPY"
        )
        |> send_resp(200, "")

      _ ->
        send_resp(conn, 405, "Method not allowed")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
