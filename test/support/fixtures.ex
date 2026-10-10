defmodule Oktavarium.Fixtures do
  @moduledoc "Pomocnicy testów: zakładanie tożsamości i dopisywanie zdarzeń przez `Log.append/1`."

  alias Oktavarium.{Crypto, Envelope, Log}

  def keypair, do: Crypto.generate_keypair()
  def key_id(keypair), do: Crypto.key_id(keypair.public)

  @doc """
  Zakłada tożsamość i zwraca jej stan: `%{id, founder, auth, seq, head}`, gdzie
  `seq` i `head` opisują ostatnie zdarzenie dziennika.
  """
  def found!(opts \\ []) do
    founder = Keyword.get(opts, :founder, keypair())
    auth = Keyword.get(opts, :auth, keypair())

    body =
      %{"kind" => Keyword.get(opts, :kind, "user"), "auth_keys" => [key_id(auth)]}
      |> then(&if(opts[:handle], do: Map.put(&1, "handle", opts[:handle]), else: &1))

    {:ok, event} = body |> Envelope.genesis(founder) |> Log.append()
    %{id: event.id, founder: founder, auth: auth, seq: 0, head: event.id}
  end

  @doc "Dopisuje zdarzenie do dziennika `state` (domyślnie podpisane kluczem założycielskim) i zwraca nowy stan."
  def next!(state, type, body, signer \\ nil) do
    {state, _event} = next_event!(state, type, body, signer)
    state
  end

  @doc "Jak `next!/4`, ale zwraca też zapisane zdarzenie."
  def next_event!(state, type, body, signer \\ nil) do
    envelope =
      Envelope.sign(
        %{type: type, seq: state.seq + 1, identity: state.id, prev: state.head, body: body},
        signer || state.founder
      )
    {:ok, event} = Log.append(envelope)
    {%{state | seq: event.seq, head: event.id}, event}
  end

  @doc "Nadaje kluczowi `subject` uprawnienie; zasób jest względny wobec tożsamości (`\"/profile/bio\"`)."
  def grant!(state, subject, action, resource_suffix, extra \\ %{}) do
    body =
      Map.merge(
        %{"subject" => key_id(subject), "action" => action, "resource" => state.id <> resource_suffix},
        extra
      )
    next_event!(state, "grant.create", body)
  end
end
