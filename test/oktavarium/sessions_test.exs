defmodule Oktavarium.SessionsTest do
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Crypto, Invites, Sessions}
  alias Oktavarium.Sessions.{Challenge, Session}

  @host "oktavarium.test"

  defp signed(auth, host \\ @host) do
    c = Sessions.challenge(host)

    sig =
      Crypto.sign(:login, Sessions.challenge_message(host, c.nonce), auth.private)
      |> Crypto.encode()

    {c.nonce, sig}
  end

  test "logowanie kluczem autoryzacji zakłada sesję z tokenem CSRF" do
    state = found!(handle: "pelagia")
    {nonce, sig} = signed(state.auth)

    assert {:ok, session} = Sessions.login(@host, nonce, key_id(state.auth), sig)
    assert %Session{key_id: key} = Sessions.get(session.token)
    assert key == key_id(state.auth)
    assert byte_size(session.csrf) > 10
    assert [%{id: id, handle: "pelagia"}] = Sessions.identities(key)
    assert id == state.id
    # w bazie nie ma samego tokenu
    refute Repo.get(Session, session.token)
  end

  test "wyzwanie jest jednorazowe" do
    state = found!()
    {nonce, sig} = signed(state.auth)
    assert {:ok, _} = Sessions.login(@host, nonce, key_id(state.auth), sig)
    assert {:error, :invalid_challenge} = Sessions.login(@host, nonce, key_id(state.auth), sig)
  end

  test "wyzwanie z innego hosta nie działa" do
    state = found!()
    {nonce, sig} = signed(state.auth, "inny.test")
    assert {:error, :invalid_challenge} = Sessions.login(@host, nonce, key_id(state.auth), sig)
  end

  test "wygasłe wyzwanie" do
    state = found!()
    {nonce, sig} = signed(state.auth)
    past = DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)
    Repo.update_all(Challenge, set: [expires_at: past])
    assert {:error, :invalid_challenge} = Sessions.login(@host, nonce, key_id(state.auth), sig)
  end

  test "zły podpis i cudzy podpis" do
    state = found!()
    {nonce, _sig} = signed(state.auth)
    wrong = Crypto.sign(:login, "cokolwiek", state.auth.private) |> Crypto.encode()
    assert {:error, :bad_signature} = Sessions.login(@host, nonce, key_id(state.auth), wrong)
    # wyzwanie zostało zużyte mimo błędu
    {nonce2, _} = signed(state.auth)
    other = keypair()

    sig =
      Crypto.sign(:login, Sessions.challenge_message(@host, nonce2), other.private)
      |> Crypto.encode()

    assert {:error, _} = Sessions.login(@host, nonce2, key_id(state.auth), sig)
  end

  test "podpis zdarzenia nie przechodzi jako podpis logowania (separacja domen)" do
    state = found!()
    c = Sessions.challenge(@host)

    sig =
      Crypto.sign(:event, Sessions.challenge_message(@host, c.nonce), state.auth.private)
      |> Crypto.encode()

    assert {:error, :bad_signature} = Sessions.login(@host, c.nonce, key_id(state.auth), sig)
  end

  test "zalogować można tylko aktywny klucz autoryzacji, nie klucz sygnowania ani nieznany" do
    state = found!()
    {nonce, _} = signed(state.founder)

    sig =
      Crypto.sign(:login, Sessions.challenge_message(@host, nonce), state.founder.private)
      |> Crypto.encode()

    assert {:error, :unknown_key} = Sessions.login(@host, nonce, key_id(state.founder), sig)

    stranger = keypair()
    {nonce, _} = signed(stranger)

    sig =
      Crypto.sign(:login, Sessions.challenge_message(@host, nonce), stranger.private)
      |> Crypto.encode()

    assert {:error, :unknown_key} = Sessions.login(@host, nonce, key_id(stranger), sig)
    assert {:error, :unknown_key} = Sessions.login(@host, nonce, "nie-klucz", sig)
  end

  test "wylogowanie i wygasanie sesji" do
    state = found!()
    {nonce, sig} = signed(state.auth)
    {:ok, session} = Sessions.login(@host, nonce, key_id(state.auth), sig)

    Sessions.logout(session.token)
    assert nil == Sessions.get(session.token)

    {nonce, sig} = signed(state.auth)
    {:ok, session} = Sessions.login(@host, nonce, key_id(state.auth), sig)
    past = DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)
    Repo.update_all(Session, set: [expires_at: past])
    assert nil == Sessions.get(session.token)
    assert nil == Sessions.get(nil)
    assert nil == Sessions.get("x")
  end

  describe "zaproszenia" do
    test "jednorazowe zaproszenie działa raz" do
      {:ok, token} = Invites.create(note: "test")
      assert :ok = Invites.consume(token)
      assert {:error, :invalid_invite} = Invites.consume(token)
    end

    test "wielokrotne, wygasłe i nieznane" do
      {:ok, many} = Invites.create(max_uses: 2)
      assert :ok = Invites.consume(many)
      assert :ok = Invites.consume(many)
      assert {:error, :invalid_invite} = Invites.consume(many)

      {:ok, old} = Invites.create(days: 1)

      Repo.update_all(Oktavarium.Invites.Invite,
        set: [expires_at: DateTime.add(DateTime.utc_now(), -5) |> DateTime.truncate(:second)]
      )

      assert {:error, :invalid_invite} = Invites.consume(old)
      assert {:error, :invalid_invite} = Invites.consume("nieistniejace-zaproszenie")
      assert {:error, :invalid_invite} = Invites.consume(nil)
    end
  end
end
