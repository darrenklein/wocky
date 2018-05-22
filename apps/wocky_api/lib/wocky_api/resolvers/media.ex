defmodule WockyAPI.Resolvers.Media do
  @moduledoc "GraphQL resolver for media objects"

  import SweetXml

  alias Wocky.Bot
  alias Wocky.Bot.Item
  alias Wocky.Repo.ID
  alias Wocky.TROS
  alias Wocky.TROS.Metadata
  alias Wocky.User

  def get_media(%User{avatar: tros_url}, _args, _info), do: get_urls(tros_url)

  def get_media(%Bot{image: tros_url}, _args, _info), do: get_urls(tros_url)

  def get_media(%Item{image: false}, _args, _info), do: {:ok, nil}

  def get_media(%Item{stanza: stanza}, _args, _info) do
    stanza
    |> xpath(~x"./image/text()"s)
    |> get_urls()
  end

  defp get_urls(nil), do: {:ok, nil}

  defp get_urls(tros_url) do
    with {:ok, {server, file_id}} <- TROS.parse_url(tros_url),
         {:ok, %Metadata{} = metadata} <- TROS.get_metadata(file_id) do
      [full_url, thumbnail_url] =
        TROS.get_download_urls(server, metadata, [:full, :thumbnail])

      {:ok,
       %{
         tros_url: tros_url,
         full_url: full_url,
         thumbnail_url: thumbnail_url
       }}
    else
      _ ->
        {:ok, %{tros_url: tros_url}}
    end
  end

  def upload(_root, args, %{context: %{current_user: user}}) do
    metadata = %{"content-type": args[:mime_type], name: args[:filename]}
    id = ID.new()

    response =
      TROS.make_upload_response(
        User.to_jid(user),
        id,
        args[:size],
        args[:access] || "",
        metadata
      )

    case response do
      {:ok, {headers, fields}} ->
        {:ok,
         %{
           id: id,
           upload_url: :proplists.get_value("url", fields),
           method: :proplists.get_value("method", fields),
           headers: make_return_headers(headers),
           reference_url: :proplists.get_value("reference_url", fields)
         }}

      {:error, e} ->
        {:error, e}
    end
  end

  defp make_return_headers(headers),
    do: Enum.map(headers, fn {n, v} -> %{name: n, value: v} end)
end
