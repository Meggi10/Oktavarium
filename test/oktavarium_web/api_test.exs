defmodule OktavariumWeb.ApiTest do
  use OktavariumWeb.ConnCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Envelope, Log}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity

  defp genesis_envelope(founder, auth, body \\ %{}) do
    Envelope.genesis(
      Map.merge(%{"kind" => "person", "auth_keys" => [key_id(auth)]}, body),
      founder
    )
  end

  defp post_envelope(conn, envelope), do: post(conn, ~p"/api/events", Envelope.to_map(envelope))

  defp event_envelope(state, type, body, signer \\ nil, seq \\ nil) do
    Envelope.sign(
      %{type: type, seq: seq || state.seq + 1, identity: state.id, prev: state.head, body: body},
      signer || state.founder
    )
  end

  describe "POST /api/events" do
    test "przyjmuje genesis i kolejne zdarzenie", %{conn: conn} do
      founder = keypair()
      envelope = genesis_envelope(founder, keypair(), %{"handle" => "pelagia"})

      body = conn |> post_envelope(envelope) |> json_response(201)
      assert %{"id" => id, "identity" => id, "seq" => 0, "type" => "identity.genesis"} = body
      assert %Identity{handle: "pelagia"} = Repo.get!(Identity, id)

      state = %{id: id, founder: founder, seq: 0, head: id}
      update = event_envelope(state, "profile.update", %{"fields" => %{"bio" => "cześć"}})

      body = build_conn() |> post_envelope(update) |> json_response(201)
      assert %{"identity" => ^id, "seq" => 1, "type" => "profile.update"} = body
      assert Repo.get!(Identity, id).profile == %{"bio" => "cześć"}
      assert :ok = Log.verify(id)
    end

    test "koperta z pliku CLI (JSON z pliku) też przechodzi", %{conn: conn} do
      json = genesis_envelope(keypair(), keypair()) |> Envelope.to_map() |> Jason.encode!()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/events", json)

      assert %{"seq" => 0} = json_response(conn, 201)
    end

    test "powtórzenie: 409 duplicate_event", %{conn: conn} do
      envelope = genesis_envelope(keypair(), keypair())
      conn |> post_envelope(envelope) |> json_response(201)

      assert %{"error" => %{"code" => "duplicate_event"}} =
               build_conn() |> post_envelope(envelope) |> json_response(409)
    end

    test "zły seq: 409 z oczekiwanym seq", %{conn: conn} do
      state = found!()
      envelope = event_envelope(state, "profile.update", %{"fields" => %{"bio" => "x"}}, nil, 5)

      assert %{"error" => %{"code" => "bad_seq", "expected_seq" => 1}} =
               conn |> post_envelope(envelope) |> json_response(409)
    end

    test "cudzy klucz: 403 not_authorized z nazwą pola", %{conn: conn} do
      state = found!()
      stranger = found!()

      envelope =
        event_envelope(
          state,
          "profile.update",
          %{"fields" => %{"bio" => "włam"}},
          stranger.founder
        )

      assert %{"error" => %{"code" => "not_authorized", "field" => "bio"}} =
               conn |> post_envelope(envelope) |> json_response(403)
    end

    test "delegat z grantem na jedno pole", %{conn: conn} do
      state = found!()
      editor = found!()
      {state, _grant} = grant!(state, editor.founder, "profile.update", "/profile/bio")

      ok =
        event_envelope(
          state,
          "profile.update",
          %{"fields" => %{"bio" => "z API"}},
          editor.founder
        )

      assert %{"seq" => 2} = conn |> post_envelope(ok) |> json_response(201)

      state = %{state | seq: 2, head: Envelope.id(ok)}

      denied =
        event_envelope(
          state,
          "profile.update",
          %{"fields" => %{"location" => "x"}},
          editor.founder
        )

      assert %{"error" => %{"code" => "not_authorized", "field" => "location"}} =
               build_conn() |> post_envelope(denied) |> json_response(403)

      assert Repo.aggregate(Grant, :count) == 1
    end

    test "niepoprawna treść zdarzenia: 422 invalid_body", %{conn: conn} do
      state = found!()
      envelope = event_envelope(state, "profile.update", %{"fields" => %{"admin" => "x"}})

      assert %{"error" => %{"code" => "invalid_body", "field" => "fields.admin"}} =
               conn |> post_envelope(envelope) |> json_response(422)
    end

    test "nieobsługiwany typ: 422", %{conn: conn} do
      state = found!()
      envelope = event_envelope(state, "repo.push", %{})

      assert %{"error" => %{"code" => "unsupported_type", "detail" => "repo.push"}} =
               conn |> post_envelope(envelope) |> json_response(422)
    end

    test "zły podpis: 400 invalid_envelope", %{conn: conn} do
      map = genesis_envelope(keypair(), keypair()) |> Envelope.to_map()

      tampered =
        Map.put(map, "signature", Base.url_encode64(:binary.copy(<<1>>, 64), padding: false))

      assert %{"error" => %{"code" => "invalid_envelope", "reason" => "bad_signature"}} =
               conn |> post(~p"/api/events", tampered) |> json_response(400)

      assert Repo.aggregate(Identity, :count) == 0
    end

    test "śmieci zamiast koperty: 400", %{conn: conn} do
      assert %{"error" => %{"code" => "invalid_envelope"}} =
               conn |> post(~p"/api/events", %{"payload" => 5}) |> json_response(400)

      assert %{"error" => %{"code" => "invalid_envelope"}} =
               build_conn()
               |> put_req_header("content-type", "application/json")
               |> post(~p"/api/events", "[1,2,3]")
               |> json_response(400)

      assert %{"error" => %{"code" => "invalid_envelope"}} =
               build_conn()
               |> put_req_header("content-type", "text/plain")
               |> post(~p"/api/events", "to nie json")
               |> json_response(400)
    end

    test "zbyt duże żądanie: 413", %{conn: conn} do
      huge = Jason.encode!(%{"payload" => String.duplicate("a", 70_000)})

      assert_error_sent 413, fn ->
        conn |> put_req_header("content-type", "application/json") |> post(~p"/api/events", huge)
      end
    end

    test "zamknięta rejestracja odrzuca genesis, ale nie kolejne zdarzenia", %{conn: conn} do
      state = found!()
      previous = Application.get_env(:oktavarium, :registration)
      Application.put_env(:oktavarium, :registration, :closed)
      on_exit(fn -> Application.put_env(:oktavarium, :registration, previous) end)

      assert %{"error" => %{"code" => "registration_closed"}} =
               conn |> post_envelope(genesis_envelope(keypair(), keypair())) |> json_response(403)

      assert Repo.aggregate(Identity, :count) == 1

      update = event_envelope(state, "profile.update", %{"fields" => %{"bio" => "nadal działa"}})
      assert %{"seq" => 1} = build_conn() |> post_envelope(update) |> json_response(201)
    end

    test "zamknięta rejestracja: uszkodzony genesis nadal dostaje invalid_envelope", %{conn: conn} do
      previous = Application.get_env(:oktavarium, :registration)
      Application.put_env(:oktavarium, :registration, :closed)
      on_exit(fn -> Application.put_env(:oktavarium, :registration, previous) end)

      map = genesis_envelope(keypair(), keypair()) |> Envelope.to_map()

      tampered =
        Map.put(map, "signature", Base.url_encode64(:binary.copy(<<1>>, 64), padding: false))

      assert %{"error" => %{"code" => "invalid_envelope"}} =
               conn |> post(~p"/api/events", tampered) |> json_response(400)
    end
  end

  describe "GET /api/identities/:id/head" do
    test "zwraca głowę dziennika", %{conn: conn} do
      state = found!()
      {state, _} = next_event!(state, "profile.update", %{"fields" => %{"bio" => "x"}})

      assert %{"identity" => id, "seq" => 1, "id" => head} =
               conn |> get(~p"/api/identities/#{state.id}/head") |> json_response(200)

      assert id == state.id
      assert head == state.head
    end

    test "nieznana tożsamość: 404", %{conn: conn} do
      assert %{"error" => %{"code" => "unknown_identity"}} =
               conn |> get(~p"/api/identities/nie-ma/head") |> json_response(404)
    end

    test "głowa pozwala delegatowi podpisać następne zdarzenie", %{conn: conn} do
      state = found!()
      editor = found!()
      {state, _} = grant!(state, editor.founder, "profile.update", "/profile/bio")

      %{"seq" => seq, "id" => head} =
        conn |> get(~p"/api/identities/#{state.id}/head") |> json_response(200)

      envelope =
        Envelope.sign(
          %{
            type: "profile.update",
            seq: seq + 1,
            identity: state.id,
            prev: head,
            body: %{"fields" => %{"bio" => "ok"}}
          },
          editor.founder
        )

      assert %{"seq" => 2} = build_conn() |> post_envelope(envelope) |> json_response(201)
    end
  end

  describe "GET /api/identities/:id/events" do
    setup do
      state = found!(handle: "alfa")

      state =
        Enum.reduce(1..3, state, fn n, acc ->
          next!(acc, "profile.update", %{"fields" => %{"bio" => "v#{n}"}})
        end)

      {:ok, state: state}
    end

    test "zwraca koperty, które da się zweryfikować po stronie klienta", %{
      conn: conn,
      state: state
    } do
      body = conn |> get(~p"/api/identities/#{state.id}/events") |> json_response(200)
      assert %{"identity" => id, "head" => 3, "events" => events} = body
      assert id == state.id
      assert length(events) == 4

      for map <- events do
        assert {:ok, envelope} = Envelope.from_map(map)
        assert {:ok, _event} = Envelope.verify(envelope)
      end
    end

    test "?after zwraca tylko nowsze zdarzenia", %{conn: conn, state: state} do
      assert %{"events" => events} =
               conn |> get(~p"/api/identities/#{state.id}/events?after=2") |> json_response(200)

      assert [%{} = map] = events
      assert {:ok, %{seq: 3}} = map |> Envelope.from_map() |> elem(1) |> Envelope.verify()

      assert %{"events" => []} =
               build_conn()
               |> get(~p"/api/identities/#{state.id}/events?after=3")
               |> json_response(200)
    end

    test "zły parametr after: 422", %{conn: conn, state: state} do
      for bad <- ["-1", "abc", "1.5", ""] do
        assert %{"error" => %{"code" => "invalid_body", "field" => "after"}} =
                 build_conn()
                 |> get(~p"/api/identities/#{state.id}/events?after=#{bad}")
                 |> json_response(422)
      end

      _ = conn
    end

    test "nieznana tożsamość: 404", %{conn: conn} do
      assert %{"error" => %{"code" => "unknown_identity"}} =
               conn |> get(~p"/api/identities/nie-ma/events") |> json_response(404)
    end
  end

  test "nieistniejąca trasa dla klienta JSON zwraca błąd w JSON", %{conn: conn} do
    conn = conn |> put_req_header("accept", "application/json") |> get("/api/nie-ma")
    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end
end
