defmodule Webdav.Handlers do
  import Plug.Conn
  require Logger

  @storage_path "./storage"

  def init(storage_path) do
    storage_path
  end

  # download file from webdav
  def handle_get(conn) do
    node_path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    if File.exists?(node_path) do
      case File.stat(node_path) do
        {:ok, stat} ->
          case stat.type do
            :regular ->
              conn
              |> put_resp_header("Content-Type", MIME.from_path(node_path))
              |> send_file(200, node_path)

            :directory ->
              with {:ok, files} <- File.ls(node_path) do
                content =
                  "<!DOCTYPE html>
                    <html>
                      <head>
                        <title>#{String.replace(node_path, @storage_path, "")}</title>
                      </head>
                      <body>
                        <h1>#{String.replace(node_path, @storage_path, "")}</h1>
                        <ul>
                          #{files |> Enum.map(fn file ->
                    current_path = String.replace(node_path, @storage_path, "") |> Path.join(file)
                    "<li><a href=\"/webdav#{current_path}\">#{file}</a></li>"
                  end) |> Enum.join("\n")}
                        </ul>
                    </body></html>"

                send_resp(conn, 200, content)
              else
                {:error, reason} ->
                  send_resp(conn, 500, "Failed to list files #{inspect(reason)}")
              end
          end

        {:error, reason} ->
          send_resp(conn, 500, "Failed to stat file #{inspect(reason)}")
      end
    else
      send_resp(conn, 404, "Not Found")
    end
  end

  # upload file in webdav
  def handle_put(conn) do
    file_path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    Logger.info("Uploading file to #{file_path}")

    case read_body(conn) do
      {:ok, body, conn} ->
        with :ok <- File.write(file_path, body) do
          send_resp(conn, 200, "File uploaded")
        else
          {:error, :enoent} ->
            send_resp(conn, 409, "Conflict")

          {:error, reason} ->
            send_resp(conn, 500, "Failed to upload file #{inspect(reason)}")
        end

      {:error, _} ->
        send_resp(conn, 400, "Bad request")
    end
  end

  # delete file from webdav
  def handle_delete(conn) do
    node_path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    case File.rm(node_path) do
      :ok ->
        send_resp(conn, 200, "File deleted")

      {:error, reason} ->
        send_resp(conn, 500, "Failed to delete file #{inspect(reason)}")
    end
  end

  # create folder in webdav
  def handle_mkcol(conn) do
    directory_path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    parent_path = Path.dirname(directory_path)

    with true <- File.exists?(parent_path) do
      case File.mkdir_p(directory_path) do
        :ok ->
          send_resp(conn, 201, "Collection created")

        {:error, :eexist} ->
          send_resp(conn, 409, "Conflict")

        {:error, :enospc} ->
          send_resp(conn, 507, "Insufficient Storage")

        {:error, reason} ->
          send_resp(conn, 500, "Failed to create folder #{inspect(reason)}")
      end
    else
      false ->
        send_resp(conn, 409, "Conflict")
    end
  end

  # propfind in webdav
  def handle_propfind(conn) do
    send_resp(conn, 200, "Hello World")
  end

  # proppatch in webdav
  def handle_proppatch(conn) do
    send_resp(conn, 200, "Hello World")
  end

  # lock in webdav
  def handle_lock(conn) do
    send_resp(conn, 200, "Hello World")
  end

  # unlock in webdav
  def handle_unlock(conn) do
    send_resp(conn, 200, "Hello World")
  end

  # move in webdav
  def handle_move(conn) do
    send_resp(conn, 200, "Hello World")
  end

  # copy in webdav
  def handle_copy(conn) do
    source_path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    destination_uri = get_req_header(conn, "destination") |> List.first()

    unless destination_uri do
      send_resp(conn, 412, "Precondition Failed")
    else
      destination_path =
        get_req_header(conn, "destination")
        |> List.first()
        |> String.replace("/webdav", "")
        |> then(&Path.join(@storage_path, &1))

      overwrite =
        get_req_header(conn, "overwrite")
        |> List.first()
        |> String.upcase()
        |> case do
          "F" -> false
          "T" -> true
          _ -> true
        end

      cond do
        source_path == destination_path ->
          send_resp(conn, 403, "Forbidden")

        not File.exists?(source_path) ->
          send_resp(conn, 404, "Not Found")

        not File.dir?(Path.dirname(destination_path)) ->
          send_resp(conn, 409, "Conflict")

        File.exists?(destination_path) and not overwrite ->
          send_resp(conn, 412, "Precondition Failed")

        true ->
          destination_existed = File.exists?(destination_path)

          result =
            if File.dir?(source_path) do
              depth =
                get_req_header(conn, "depth")
                |> List.first()
                |> case do
                  "0" -> 0
                  "1" -> 1
                  "infinity" -> :infinity
                  _ -> :infinity
                end

              case depth do
                :infinity ->
                  File.cp_r(source_path, destination_path)

                0 ->
                  File.mkdir_p(destination_path)

                1 ->
                  File.mkdir_p(destination_path)

                  File.ls(source_path)
                  |> Enum.each(fn file ->
                    unless File.dir?(Path.join(source_path, file)) do
                      File.cp(Path.join(source_path, file), Path.join(destination_path, file))
                    end
                  end)
              end

              {:ok, :directory}
            else
              case File.cp(source_path, destination_path) do
                :ok -> {:ok, :file}
                error -> error
              end
            end

          case result do
            {:ok, :directory} ->
              status = if destination_existed, do: 204, else: 201
              send_resp(conn, status, "Copied")

            {:ok, :file} ->
              status = if destination_existed, do: 204, else: 201
              send_resp(conn, status, "Copied")

            {:error, reason} ->
              send_resp(conn, 500, "Failed to copy: #{inspect(reason)}")
          end
      end
    end
  end
end

# TODO:
# - handle propfind
# - handle copy collection response in html
