defmodule Webdav.Application do
  use Application
  require Logger

  def start(_type, args) do
    {opts, _} =
      OptionParser.parse!(System.argv(),
        strict: [storage_path: :string],
        aliases: [s: :storage_path]
      )

    storage_path = Keyword.get(opts, :storage_path, "./storage")

    if not File.exists?(storage_path) do
      File.mkdir_p!(storage_path)
    end

    port = Keyword.get(args, :port, 8080)

    Webdav.Handlers.init(storage_path)

    Logger.info("Starting WebDAV server on port #{port}")

    children = [
      {Plug.Cowboy, scheme: :http, plug: Webdav.Router, options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: Webdav.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
