defmodule Oktavarium.Sessions do
  @moduledoc false
  import Ecto.Query

  alias Oktavarium.{Crypto, Repo}
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.{IdentityAuthKey, Key}
  alias Oktavarium.Sessions.{Challenge, Session}

  @challenge_ttl 300
  @session_ttl 7 * 24 * 3600

  def session_ttl, do: @session_ttl

  @doc "Wystawia wyzwanie dla `host`. Zwraca `%{nonce, host, expires_at}`."
  @spec challenge(String.t()) :: map()
  def challenge(host) when is_binary(host) do
    purge()
    nonce = random()
    expires_at = in_seconds(@challenge_ttl)
    Repo.insert!(%Challenge{nonce: nonce, host: host, expires_at: expires_at})
    %{nonce: nonce, host: host, expires_at: expires_at}
  end

  @doc "Treść, którą klient podpisuje w domenie `:login`."
  def challenge_message(host, nonce), do: host <> "\n" <> nonce

  @doc """
  Loguje kluczem autoryzacji. Zwraca `{:ok, %{token, csrf, key_id, expires_at}}` albo
  `{:error, :invalid_challenge | :bad_signature | :unknown_key}`.
  """
  @spec login(String.t(), String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def login(host, nonce, key_id, signature)
      when is_binary(nonce) and is_binary(key_id) and is_binary(signature) do
    Repo.transaction(fn ->
      with {:ok, challenge} <- take_challenge(nonce, host),
           {:ok, public} <- decode_key(key_id),
           {:ok, sig} <- decode(signature),
           :ok <- verify(challenge, public, sig),
           :ok <- check_key(key_id) do
        create(key_id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, reason}
    end
  end

  def login(_host, _nonce, _key_id, _signature), do: {:error, :invalid_challenge}

  @doc "Sesja po tokenie z ciasteczka albo `nil`."
  @spec get(String.t() | nil) :: Session.t() | nil
  def get(token) when is_binary(token) and byte_size(token) in 20..100 do
    now = DateTime.utc_now()

    session =
      Repo.one(from s in Session, where: s.token_hash == ^hash(token) and s.expires_at > ^now)

    # klucz, któremu cofnięto wszystkie powiązania, traci też działające sesje
    if session && identities(session.key_id) != [], do: session
  end

  def get(_other), do: nil

  @doc "Kończy sesję."
  def logout(token) when is_binary(token) do
    Repo.delete_all(from s in Session, where: s.token_hash == ^hash(token))
    :ok
  end

  def logout(_other), do: :ok

  @doc """
  Tożsamości, w których klucz autoryzacji sesji jest aktywny:
  `[%{id, handle, kind, display_name}]`.
  """
  @spec identities(String.t()) :: [map()]
  def identities(key_id) do
    Repo.all(
      from l in IdentityAuthKey,
        join: i in Identity,
        on: i.id == l.identity_id,
        where: l.key_id == ^key_id and l.status == :active,
        order_by: [asc: i.inserted_at, asc: i.id],
        select: %{id: i.id, handle: i.handle, kind: i.kind, profile: i.profile}
    )
    |> Enum.map(fn i ->
      %{
        id: i.id,
        handle: i.handle,
        kind: i.kind,
        display_name: get_in(i.profile || %{}, ["display_name"])
      }
    end)
  end

  @doc "Usuwa wygasłe wyzwania i sesje."
  def purge do
    now = DateTime.utc_now()
    Repo.delete_all(from c in Challenge, where: c.expires_at <= ^now)
    Repo.delete_all(from s in Session, where: s.expires_at <= ^now)
    :ok
  end

  # wnętrze

  defp take_challenge(nonce, host) do
    now = DateTime.utc_now()

    # `delete_all` jest atomowe: dwa równoległe logowania z tym samym nonce'em nie
    # zużyją go oba
    case Repo.delete_all(
           from c in Challenge,
             where: c.nonce == ^nonce and c.host == ^host and c.expires_at > ^now
         ) do
      {1, _} -> {:ok, %{nonce: nonce, host: host}}
      _ -> {:error, :invalid_challenge}
    end
  end

  defp verify(%{host: host, nonce: nonce}, public, signature) do
    if Crypto.verify(:login, challenge_message(host, nonce), signature, public),
      do: :ok,
      else: {:error, :bad_signature}
  end

  defp check_key(key_id) do
    linked? =
      Repo.exists?(
        from l in IdentityAuthKey,
          join: k in Key,
          on: k.id == l.key_id,
          where:
            l.key_id == ^key_id and l.status == :active and k.kind == :auth and
              k.status == :active
      )

    if linked?, do: :ok, else: {:error, :unknown_key}
  end

  defp create(key_id) do
    token = random(32)
    csrf = random(16)
    expires_at = in_seconds(@session_ttl)

    Repo.insert!(%Session{
      token_hash: hash(token),
      key_id: key_id,
      csrf: csrf,
      expires_at: expires_at
    })

    %{token: token, csrf: csrf, key_id: key_id, expires_at: expires_at}
  end

  defp decode_key(id) do
    case Crypto.decode_key_id(id) do
      {:ok, public} -> {:ok, public}
      :error -> {:error, :unknown_key}
    end
  end

  defp decode(string) do
    case Crypto.decode(string) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :bad_signature}
    end
  end

  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  defp random(bytes \\ 16), do: bytes |> :crypto.strong_rand_bytes() |> Crypto.encode()

  defp in_seconds(n),
    do: DateTime.utc_now() |> DateTime.add(n, :second) |> DateTime.truncate(:second)
end
