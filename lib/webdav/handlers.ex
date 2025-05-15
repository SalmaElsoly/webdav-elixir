defmodule Webdav.Handlers do
  import Plug.Conn
  require Logger
  import SweetXml
  import UUID, only: [uuid4: 0]
  @storage_path "./storage"
  @metadata_path "./metadata"

  def init(storage_path) do
    File.mkdir_p(@metadata_path)
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
              case File.ls(node_path) do
                {:ok, files} ->
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
                      "<li><a href=\"/webdav/#{current_path}\">#{file}</a></li>"
                    end) |> Enum.join("\n")}
                        </ul>
                    </body></html>"

                  send_resp(conn, 200, content)

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

    exists = File.exists?(file_path)

    case check_lock(conn, file_path) do
      :ok ->
        case read_body(conn) do
          {:ok, body, conn} ->

            case File.write(file_path, body) do
              :ok ->
                if exists do
                  send_resp(conn, 204, "")
                else
                  send_resp(conn, 201, "File Uploaded")
                end

              {:error, :enoent} ->
                send_resp(conn, 409, "Conflict")

              {:error, reason} ->
                send_resp(conn, 500, "Failed to upload file #{inspect(reason)}")
            end

          {:error, _} ->
            send_resp(conn, 400, "Bad request")
        end

      {:error, :locked} ->
        send_resp(conn, 423, "Resource is locked")
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

    case File.exists?(parent_path) do
      true ->
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

      false ->
        send_resp(conn, 409, "Conflict")
    end
  end

  # propfind in webdav
  def handle_propfind(conn) do
    path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    depth =
      get_req_header(conn, "depth")
      |> List.first()
      |> case do
        "0" -> 0
        "1" -> 1
        "infinity" -> :infinity
        _ -> :infinity
      end

    if File.exists?(path) do
      properties = parse_xml_body(conn)
      Logger.info("Properties: #{inspect(properties)}")

      try do
        conn
        |> put_resp_header("Content-Type", "application/xml; charset=utf-8")
        |> send_resp(207, xml_builder(path, properties, depth))
      rescue
        e ->
          send_resp(conn, 400, "Bad Request #{inspect(e)}")
      end
    else
      send_resp(conn, 404, "Not Found")
    end
  end

  # proppatch in webdav
  def handle_proppatch(conn) do
    path =
      conn.request_path
      |> String.replace("/webdav", "")
      |> then(&Path.join(@storage_path, &1))

    if File.exists?(path) do
      case check_lock(conn, path) do
        :ok ->
          case read_body(conn) do
            {:ok, body, _conn} when byte_size(body) > 0 ->
              try do
                property_updates = parse_proppatch_xml(body)

                save_properties(path, property_updates)

                response_xml = build_proppatch_response(path, property_updates)

                conn
                |> put_resp_header("Content-Type", "application/xml; charset=utf-8")
                |> send_resp(207, response_xml)
              rescue
                e ->
                  Logger.error("Error handling PROPPATCH: #{inspect(e)}")
                  send_resp(conn, 400, "Bad Request")
              end

            _ ->
              send_resp(conn, 400, "Bad Request")
          end

        {:error, :locked} ->
          send_resp(conn, 423, "Resource is locked")
      end
    else
      send_resp(conn, 404, "Not Found")
    end
  end

  # lock in webdav
  def handle_lock(conn) do
    path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    depth =
      get_req_header(conn, "depth")
      |> List.first()
      |> case do
        "0" -> 0
        "1" -> 1
        "infinity" -> :infinity
        _ -> :infinity
      end

    timeout =
      get_req_header(conn, "timeout")
      |> List.first()
      |> case do
        "Infinite" -> "Infinite"
        _ -> "#{get_req_header(conn, "timeout") |> List.first()}"
      end

    file_exists = File.exists?(path)

    unless file_exists do
      Logger.info("Creating lock-null resource for #{path}")
    end

    xml_properties = lock_xml_parser(conn)

    Logger.info("Lock properties: #{inspect(xml_properties)}")

    lock_token = "opaquelocktoken:" <> uuid4()

    apply_lock = fn file_path, lock_token ->
      lock_properties = %{
        "locktype" => %{action: :set, value: xml_properties["locktype"]},
        "lockscope" => %{action: :set, value: xml_properties["lockscope"]},
        "locktoken" => %{action: :set, value: lock_token},
        "locktimeout" => %{action: :set, value: timeout}
      }

      save_properties(file_path, lock_properties)
    end

    case depth do
      :infinity ->
        if file_exists do
          recursive_lock(path, apply_lock, lock_token)
        else
          apply_lock.(path, lock_token)
        end

      0 ->
        apply_lock.(path, lock_token)

      1 ->
        apply_lock.(path, lock_token)

        if file_exists and File.dir?(path) do
          File.ls(path)
          |> case do
            {:ok, files} ->
              files
              |> Enum.each(fn file ->
                apply_lock.(Path.join(path, file), lock_token)
              end)

            {:error, reason} ->
              send_resp(conn, 500, "Failed to list files #{inspect(reason)}")
          end
        end

      _ ->
        send_resp(conn, 409, "Conflict")
    end

    xml_response = """
    <?xml version="1.0" encoding="utf-8" ?>
    <D:prop xmlns:D="DAV:">
    <D:lockdiscovery>
        <D:activelock>
             <D:locktype>#{xml_properties["locktype"]}</D:locktype>
             <D:lockscope>#{xml_properties["lockscope"]}</D:lockscope>
             <D:depth>#{depth}</D:depth>
             <D:owner>
                  <D:href>
                    #{xml_properties["owner"]}
                  </D:href>
             </D:owner>
             <D:timeout>#{timeout}</D:timeout>
             <D:locktoken>
                  <D:href>
                    #{lock_token}
                  </D:href>
             </D:locktoken>
        </D:activelock>
    </D:lockdiscovery>
    </D:prop>
    """

    conn
    |> put_resp_header("Lock-Token", lock_token)
    |> put_resp_header("Content-Type", "application/xml; charset=utf-8")
    |> send_resp(200, xml_response)
  end

  defp recursive_lock(path, apply_lock, lock_token) do
    if File.dir?(path) do
      File.ls(path)
      |> Enum.each(fn file ->
        recursive_lock(Path.join(path, file), apply_lock, lock_token)
      end)
    else
      apply_lock.(path, lock_token)
    end
  end

  # unlock in webdav
  def handle_unlock(conn) do
    path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    lock_token =
      get_req_header(conn, "lock-token")
      |> List.first()
      |> case do
        nil -> nil
        token -> String.trim(token, "<") |> String.trim(">")
      end

    if File.exists?(path) and lock_token do
      unlock_recursive(path, lock_token)
      send_resp(conn, 204, "")
    else
      send_resp(conn, 404, "Not Found")
    end
  end

  defp unlock_recursive(path, lock_token) do
    custom_properties = get_custom_properties(path)
    stored_lock_token = custom_properties["locktoken"]

    lock_props = ["locktoken", "locktimeout", "locktype", "lockscope"]
    removal_map = Enum.into(lock_props, %{}, fn prop -> {prop, %{action: :remove}} end)

    removed =
      if stored_lock_token == lock_token do
        save_properties(path, removal_map)
        true
      else
        false
      end

    if File.dir?(path) do
      File.ls!(path)
      |> Enum.reduce(removed, fn file, acc ->
        unlock_recursive(Path.join(path, file), lock_token) or acc
      end)
    else
      removed
    end
  end

  # move in webdav
  def handle_move(conn) do
    with {:ok, source_path, destination_path} <- move_copy_options(conn),
         :ok <- check_lock(conn, source_path),
         :ok <- check_lock(conn, destination_path) do
      cond do
        File.exists?(destination_path) ->
          File.rename(source_path, destination_path)
          send_resp(conn, 204, "Moved")

        true ->
          File.rename(source_path, destination_path)
          send_resp(conn, 201, "Moved")
      end
    else
      {:error, :locked} ->
        send_resp(conn, 423, "Resource is locked")

      error ->
        error
    end
  end

  # copy in webdav
  def handle_copy(conn) do
    with {:ok, source_path, destination_path} <- move_copy_options(conn),
         :ok <- check_lock(conn, source_path),
         :ok <- check_lock(conn, destination_path) do
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
        else
          File.cp(source_path, destination_path)
        end

      case result do
        :ok ->
          if destination_existed,
            do: send_resp(conn, 204, "Copied"),
            else: send_resp(conn, 201, "Copied")

        {:error, reason} ->
          send_resp(conn, 500, "Failed to copy: #{inspect(reason)}")
      end
    else
      {:error, :locked} ->
        send_resp(conn, 423, "Resource is locked")

      error ->
        error
    end
  end

  defp move_copy_options(conn) do
    source_path =
      conn.request_path |> String.replace("/webdav", "") |> then(&Path.join(@storage_path, &1))

    destination_uri = get_req_header(conn, "destination") |> List.first()

    unless destination_uri do
      send_resp(conn, 412, "Precondition Failed")
    else
      destination_path =
        get_req_header(conn, "destination")
        |> List.first()
        |> URI.parse()
        |> Map.get(:path)
        |> String.replace("/webdav", "")
        |> then(&Path.join(@storage_path, &1))

      overwrite =
        get_req_header(conn, "overwrite")
        |> List.first()
        |> case do
          nil -> true
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
          {:ok, source_path, destination_path}
      end
    end
  end

  defp parse_xml_body(conn) do
    case read_body(conn) do
      {:ok, body, _conn} when byte_size(body) > 0 ->
        try do
          all_props = body |> xpath(~x"//D:allprop"l)

          Logger.info("All props: #{inspect(all_props)}")

          if length(all_props) > 0 do
            [
              "getcontentlength",
              "getlastmodified",
              "resourcetype",
              "creationdate",
              "getcontenttype",
              "displayname",
              "getcontentlanguage",
              "getetag"
            ]
          else
            props =
              body
              |> xpath(~x"//D:prop/*"l)
              |> Enum.map(fn node -> node |> xpath(~x"local-name()"s) end)

            if Enum.empty?(props) do
              ["getcontentlength", "getlastmodified", "resourcetype", "creationdate"]
            else
              props
            end
          end
        rescue
          e ->
            Logger.error("Error parsing propfind: #{inspect(e)}")
            ["getcontentlength", "getlastmodified", "resourcetype", "creationdate"]
        end

      _ ->
        ["getcontentlength", "getlastmodified", "resourcetype", "creationdate"]
    end
  end

  defp xml_builder(path, properties, depth) do
    response = build_response(path, properties)

    children =
      if depth > 0 and File.dir?(path) do
        case File.ls(path) do
          {:ok, files} ->
            files
            |> Enum.map(fn file -> build_response(Path.join(path, file), properties) end)
            |> Enum.join("\n")

          {:error, reason} ->
            Logger.error("Error listing files: #{inspect(reason)}")
            ""
        end
      else
        ""
      end

    """
    <D:multistatus xmlns:D="DAV:">
      #{response}
      #{children}
    </D:multistatus>
    """
  end

  defp build_response(path, properties) do
    custom_props = get_custom_properties(path)

    """
    <D:response>
      <D:href>#{String.replace(path, @storage_path, "/webdav")}</D:href>
      <D:propstat>
        <D:prop>
          #{properties |> Enum.map(fn prop -> """
      <D:#{prop}>
      #{case prop do
        "getcontentlength" -> File.stat!(path).size
        "getlastmodified" -> File.stat!(path).mtime |> format_datetime()
        "resourcetype" -> if File.dir?(path), do: "<D:collection/>", else: ""
        "creationdate" -> File.stat!(path).mtime |> format_datetime()
        "getcontenttype" -> MIME.from_path(path)
        "displayname" -> String.replace(path, @storage_path, "")
        "getcontentlanguage" -> "en"
        "getetag" -> "W/\"#{path}\""
        prop when is_map_key(custom_props, prop) -> custom_props[prop]
        _ -> ""
      end}
      </D:#{prop}>
      """ end) |> Enum.join("\n")}
        </D:prop>
        <D:status>HTTP/1.1 200 OK</D:status>
      </D:propstat>
    </D:response>
    """
  end

  defp format_datetime({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad_number(month)}-#{pad_number(day)}T#{pad_number(hour)}:#{pad_number(minute)}:#{pad_number(second)}Z"
  end

  defp pad_number(number) when number < 10, do: "0#{number}"
  defp pad_number(number), do: "#{number}"

  defp parse_proppatch_xml(body) do
    property_sets = body |> xpath(~x"//D:set/D:prop/*"l)
    property_removes = body |> xpath(~x"//D:remove/D:prop/*"l)

    set_properties =
      property_sets
      |> Enum.map(fn node ->
        name = node |> xpath(~x"local-name()"s)
        value = node |> xpath(~x"text()"s)
        {name, %{action: :set, value: value}}
      end)
      |> Enum.into(%{})

    remove_properties =
      property_removes
      |> Enum.map(fn node ->
        name = node |> xpath(~x"local-name()"s)
        {name, %{action: :remove}}
      end)
      |> Enum.into(%{})

    Map.merge(set_properties, remove_properties)
  end

  defp save_properties(path, property_updates) do
    relative_path = String.replace(path, @storage_path, "")

    metadata_file =
      Path.join(
        @metadata_path,
        "#{:crypto.hash(:md5, relative_path) |> Base.encode16(case: :lower)}.json"
      )

    properties =
      if File.exists?(metadata_file) do
        metadata_file
        |> File.read!()
        |> Jason.decode!()
      else
        %{}
      end

    unchangable_properties = [
      "creationdate",
      "getcontentlength",
      "getlastmodified",
      "resourcetype",
      "displayname",
      "getcontenttype",
      "getetag",
      "getcontentlanguage"
    ]

    updated_properties =
      Enum.reduce(property_updates, properties, fn {name, details}, acc ->
        if name in unchangable_properties do
          acc
        else
          case details.action do
            :set -> Map.put(acc, name, details.value)
            :remove -> Map.delete(acc, name)
          end
        end
      end)

    File.write!(metadata_file, Jason.encode!(updated_properties))
  end

  defp build_proppatch_response(path, property_updates) do
    href = String.replace(path, @storage_path, "")

    unchangable_properties = [
      "creationdate",
      "getcontentlength",
      "getlastmodified",
      "resourcetype",
      "displayname",
      "getcontenttype",
      "getetag",
      "getcontentlanguage"
    ]

    propstat_elements =
      property_updates
      |> Enum.map(fn {name, _details} ->
        status =
          if name in unchangable_properties do
            "HTTP/1.1 409 Conflict"
          else
            "HTTP/1.1 200 OK"
          end

        """
        <D:propstat>
          <D:prop>
            <D:#{name}/>
          </D:prop>
          <D:status>#{status}</D:status>
        </D:propstat>
        """
      end)
      |> Enum.join("\n")

    """
    <D:multistatus xmlns:D="DAV:">
      <D:response>
        <D:href>#{href}</D:href>
        #{propstat_elements}
      </D:response>
    </D:multistatus>
    """
  end

  defp get_custom_properties(path) do
    relative_path = String.replace(path, @storage_path, "")

    metadata_file =
      Path.join(
        @metadata_path,
        "#{:crypto.hash(:md5, relative_path) |> Base.encode16(case: :lower)}.json"
      )

    if File.exists?(metadata_file) do
      metadata_file
      |> File.read!()
      |> Jason.decode!()
    else
      %{}
    end
  end

  defp lock_xml_parser(conn) do
    case read_body(conn) do
      {:ok, body, _conn} when byte_size(body) > 0 ->
        Logger.info("Body: #{inspect(body)}")
        body
        |> xpath(~x"//lockinfo/*"l)
        |> Enum.map(fn node ->
          name = node |> xpath(~x"local-name()"s)
          has_children = node |> xpath(~x"count(./*)"i) > 0
          value = if has_children, do: node |> xpath(~x"*[1]/local-name()"s), else: node |> xpath(~x"text()"s)
          {name, value}
        end)
        |> Enum.into(%{})
      _ ->
        %{}
    end
  end

  defp check_lock(conn, path) do
    custom_properties = get_custom_properties(path)
    stored_lock_token = custom_properties["locktoken"]

    if stored_lock_token do
      provided_lock_token =
        get_req_header(conn, "if")
        |> List.first()
        |> case do
          nil -> nil
          token -> String.trim(token, "<") |> String.trim(">")
        end

      if provided_lock_token == stored_lock_token do
        :ok
      else
        {:error, :locked}
      end
    else
      :ok
    end
  end
end

# TODO:
# - handle lock
# - handle unlock
