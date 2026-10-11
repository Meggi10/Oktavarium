defmodule OktavariumWeb.Components do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: OktavariumWeb.Endpoint,
    router: OktavariumWeb.Router,
    statics: OktavariumWeb.static_paths()

  @months ~w(sty lut mar kwi maj cze lip sie wrz paź lis gru)

  @doc "Skrót długiego identyfikatora (klucza, zdarzenia, tożsamości); krótkie zostają bez zmian."
  @spec short(String.t()) :: String.t()
  def short(id) when is_binary(id) and byte_size(id) > 14 do
    binary_part(id, 0, 6) <> "…" <> binary_part(id, byte_size(id) - 4, 4)
  end

  def short(id) when is_binary(id), do: id

  @doc "Polska nazwa rodzaju tożsamości."
  def kind_name(kind) when kind in [:person, "person"], do: "osoba"
  def kind_name(kind) when kind in [:collective, "collective"], do: "kolektyw"
  def kind_name(_other), do: "tożsamość"

  @doc "Odmiana: `plural(1, \"zdarzenie\", \"zdarzenia\", \"zdarzeń\")`."
  def plural(1, one, _few, _many), do: "1 " <> one

  def plural(n, _one, few, many) when is_integer(n) do
    last = rem(n, 10)
    teens = rem(n, 100)

    if last in 2..4 and teens not in 12..14,
      do: "#{n} #{few}",
      else: "#{n} #{many}"
  end

  @doc "Czas w UTC po polsku, np. `6 paź 2026, 12:00 UTC`."
  @spec format_time(DateTime.t() | NaiveDateTime.t()) :: String.t()
  def format_time(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> format_time()

  def format_time(%DateTime{} = at) do
    "#{at.day} #{Enum.at(@months, at.month - 1)} #{at.year}, #{Calendar.strftime(at, "%H:%M")} UTC"
  end

  @doc "Czas z sekund unixowych (jak w ładunku zdarzenia) albo `nil`."
  def from_unix(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, at} -> at
      {:error, _} -> nil
    end
  end

  def from_unix(_other), do: nil

  attr :at, :any, required: true

  def time_tag(assigns) do
    assigns = assign(assigns, :iso, assigns.at |> to_utc() |> DateTime.to_iso8601())

    ~H"""
    <time datetime={@iso}>{format_time(@at)}</time>
    """
  end

  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_utc(%DateTime{} = at), do: at

  attr :id, :string, required: true

  def key_id(assigns) do
    ~H"""
    <code class="hash" title={@id}>{short(@id)}</code>
    """
  end

  attr :key_id, :string, required: true
  attr :homes, :map, required: true

  @doc "Klucz jako link do tożsamości, do której należy, a gdy jej nie znamy, jako skrót."
  def holder(assigns) do
    assigns = assign(assigns, :home, Map.get(assigns.homes, assigns.key_id))

    ~H"""
    <a :if={@home && @home.handle} class="holder" href={~p"/i/#{@home.handle}"}>@{@home.handle}</a>
    <a :if={@home && !@home.handle} class="holder" href={~p"/i/#{@home.identity_id}"}>{short(
      @home.identity_id
    )}</a>
    <.key_id :if={!@home} id={@key_id} />
    """
  end
end
