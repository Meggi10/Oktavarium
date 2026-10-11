defmodule OktavariumWeb.BrowserApiTest do
  use OktavariumWeb.ConnCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Blobs, Crypto, Envelope, Invites}

  @png <<0x89, "PNG\r\n", 0x1A, "\n", "obrazek">>
  @mp3 "ID3" <> <<3, 0, 0, 1, 2, 3, 4>>

  defp hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp login(conn, state) do
    c = conn |> post(~p"/api/session/challenge") |> json_response(200)
    sig = Crypto.sign(:login, c["message"], state.auth.private) |> Crypto.encode()

    conn =
      post(build_conn(), ~p"/api/session", %{
        nonce: c["nonce"],
        key: key_id(state.auth),
        signature: sig
      })

    body = json_response(conn, 200)
    {recycle(conn), body["csrf"], body}
  end

  defp upload(conn, csrf, bytes, type) do
    conn
    |> put_req_header("content-type", type)
    |> put_req_header("x-csrf-token", csrf)
    |> post(~p"/api/blobs", bytes)
  end

  defp put_resource(state, path, bytes, type, extra \\ %{}) do
    body =
      Map.merge(
        %{
          "path" => path,
          "hash" => hash(bytes),
          "size" => byte_size(bytes),
          "media_type" => type
        },
        extra
      )

    next!(state, "resource.put", body)
  end

  describe "sesja" do
    test "logowanie, /api/me i wylogowanie", %{conn: conn} do
      state = found!(handle: "pelagia")
      {session_conn, csrf, body} = login(conn, state)

      assert body["key"] == key_id(state.auth)
      assert [%{"handle" => "pelagia"}] = body["identities"]
      assert %{"csrf" => ^csrf} = session_conn |> get(~p"/api/me") |> json_response(200)

      assert %{"error" => %{"code" => "invalid_csrf"}} =
               session_conn |> delete(~p"/api/session") |> json_response(403)

      out = session_conn |> put_req_header("x-csrf-token", csrf) |> delete(~p"/api/session")
      assert json_response(out, 200)

      assert %{"error" => %{"code" => "unauthenticated"}} =
               build_conn() |> get(~p"/api/me") |> json_response(401)

      assert %{"error" => %{"code" => "unauthenticated"}} =
               recycle(out) |> get(~p"/api/me") |> json_response(401)
    end

    test "ciasteczko ma HttpOnly i SameSite=Strict", %{conn: conn} do
      state = found!()
      c = conn |> post(~p"/api/session/challenge") |> json_response(200)
      sig = Crypto.sign(:login, c["message"], state.auth.private) |> Crypto.encode()

      out =
        post(build_conn(), ~p"/api/session", %{
          nonce: c["nonce"],
          key: key_id(state.auth),
          signature: sig
        })

      assert response(out, 200)

      cookie =
        out
        |> get_resp_cookies()
        |> Map.fetch!(OktavariumWeb.Auth.cookie_name())

      assert cookie.http_only == true
      assert cookie.same_site == "Strict"
      refute Map.has_key?(cookie, :domain)
    end

    test "zły podpis: 401", %{conn: conn} do
      state = found!()
      c = conn |> post(~p"/api/session/challenge") |> json_response(200)
      sig = Crypto.sign(:login, "inne", state.auth.private) |> Crypto.encode()

      assert %{"error" => %{"code" => "bad_signature"}} =
               build_conn()
               |> post(~p"/api/session", %{
                 nonce: c["nonce"],
                 key: key_id(state.auth),
                 signature: sig
               })
               |> json_response(401)

      assert %{"error" => %{"code" => "invalid_body"}} =
               build_conn() |> post(~p"/api/session", %{}) |> json_response(422)
    end
  end

  describe "bloby" do
    test "wysyłanie wymaga sesji i CSRF", %{conn: conn} do
      state = found!()

      assert %{"error" => %{"code" => "unauthenticated"}} =
               conn
               |> put_req_header("content-type", "image/png")
               |> post(~p"/api/blobs", @png)
               |> json_response(401)

      {session_conn, csrf, _} = login(build_conn(), state)

      assert %{"error" => %{"code" => "invalid_csrf"}} =
               session_conn
               |> put_req_header("content-type", "image/png")
               |> post(~p"/api/blobs", @png)
               |> json_response(403)

      assert %{"hash" => h, "size" => size, "media_type" => "image/png"} =
               session_conn |> upload(csrf, @png, "image/png") |> json_response(201)

      assert h == hash(@png) and size == byte_size(@png)
    end

    test "zły typ, nieznany typ", %{conn: conn} do
      state = found!()
      {session_conn, csrf, _} = login(conn, state)

      assert %{"error" => %{"code" => "media_type_mismatch"}} =
               session_conn |> upload(csrf, @png, "audio/mpeg") |> json_response(415)

      assert %{"error" => %{"code" => "unsupported_media_type"}} =
               session_conn |> upload(csrf, "echo", "application/x-sh") |> json_response(415)
    end

    test "serwuje tylko publiczne obrazy i audio, z Range i nagłówkami bezpieczeństwa", %{
      conn: conn
    } do
      state = found!(handle: "pelagia")
      {:ok, _} = Blobs.put(@png, "image/png")
      {:ok, _} = Blobs.put(@mp3, "audio/mpeg")

      # niezwiązany z żadnym zasobem: 404
      assert conn |> get("/blobs/#{hash(@png)}") |> response(404)

      state = put_resource(state, "images/a.png", @png, "image/png")
      _ = put_resource(state, "audio/a.mp3", @mp3, "audio/mpeg")

      ok = get(build_conn(), "/blobs/#{hash(@png)}")
      assert response(ok, 200) == @png
      assert get_resp_header(ok, "content-type") == ["image/png"]
      assert get_resp_header(ok, "x-content-type-options") == ["nosniff"]
      assert [csp] = get_resp_header(ok, "content-security-policy")
      assert csp =~ "sandbox"

      partial =
        build_conn() |> put_req_header("range", "bytes=0-3") |> get("/blobs/#{hash(@mp3)}")

      assert response(partial, 206) == binary_part(@mp3, 0, 4)
      assert get_resp_header(partial, "content-range") == ["bytes 0-3/#{byte_size(@mp3)}"]

      bad = build_conn() |> put_req_header("range", "bytes=999-") |> get("/blobs/#{hash(@mp3)}")
      assert response(bad, 416)

      assert build_conn() |> get("/blobs/nie-hash") |> response(404)
    end

    test "plik strony (html) nie jest serwowany z głównej domeny", %{conn: conn} do
      state = found!(handle: "pelagia")
      html = "<script>alert(1)</script>"
      {:ok, _} = Blobs.put(html, "text/html")
      _ = put_resource(state, "site/index.html", html, "text/html")
      assert conn |> get("/blobs/#{hash(html)}") |> response(404)
    end

    test "niepubliczna tożsamość nie wystawia blobów", %{conn: conn} do
      state = found!(handle: "cicha")
      {:ok, _} = Blobs.put(@png, "image/png")
      _ = put_resource(state, "images/a.png", @png, "image/png")
      Repo.update_all(Oktavarium.Identities.Identity, set: [visibility: :restricted])
      assert conn |> get("/blobs/#{hash(@png)}") |> response(404)
    end
  end

  describe "resource.put przez API" do
    test "wymaga istniejącego bloba o zgodnych polach", %{conn: conn} do
      state = found!()

      body = %{
        "path" => "images/a.png",
        "hash" => hash(@png),
        "size" => byte_size(@png),
        "media_type" => "image/png"
      }

      envelope =
        Envelope.sign(
          %{type: "resource.put", seq: 1, identity: state.id, prev: state.head, body: body},
          state.founder
        )

      assert %{"error" => %{"code" => "blob_not_found"}} =
               conn |> post(~p"/api/events", Envelope.to_map(envelope)) |> json_response(404)

      {:ok, _} = Blobs.put(@png, "image/png")

      wrong = Map.put(body, "size", 1)

      bad =
        Envelope.sign(
          %{type: "resource.put", seq: 1, identity: state.id, prev: state.head, body: wrong},
          state.founder
        )

      assert %{"error" => %{"code" => "invalid_body"}} =
               build_conn() |> post(~p"/api/events", Envelope.to_map(bad)) |> json_response(422)

      assert %{"type" => "resource.put"} =
               build_conn()
               |> post(~p"/api/events", Envelope.to_map(envelope))
               |> json_response(201)
    end
  end

  describe "zamknięta rejestracja z zaproszeniami" do
    setup do
      previous = Application.get_env(:oktavarium, :registration)
      Application.put_env(:oktavarium, :registration, :closed)
      on_exit(fn -> Application.put_env(:oktavarium, :registration, previous) end)
    end

    defp genesis(body \\ %{}),
      do:
        Envelope.genesis(
          Map.merge(%{"kind" => "user", "auth_keys" => [key_id(keypair())]}, body),
          keypair()
        )

    test "bez zaproszenia i ze złym: 403", %{conn: conn} do
      assert %{"error" => %{"code" => "registration_closed"}} =
               conn |> post(~p"/api/events", Envelope.to_map(genesis())) |> json_response(403)

      assert %{"error" => %{"code" => "invalid_invite"}} =
               build_conn()
               |> put_req_header("x-oktavarium-invite", "to-na-pewno-nie-jest-zaproszenie")
               |> post(~p"/api/events", Envelope.to_map(genesis()))
               |> json_response(403)
    end

    test "z ważnym zaproszeniem genesis przechodzi, a zaproszenie się zużywa", %{conn: conn} do
      {:ok, token} = Invites.create()

      assert %{"seq" => 0} =
               conn
               |> put_req_header("x-oktavarium-invite", token)
               |> post(~p"/api/events", Envelope.to_map(genesis()))
               |> json_response(201)

      assert %{"error" => %{"code" => "invalid_invite"}} =
               build_conn()
               |> put_req_header("x-oktavarium-invite", token)
               |> post(~p"/api/events", Envelope.to_map(genesis()))
               |> json_response(403)
    end

    test "odrzucony genesis nie spala zaproszenia", %{conn: conn} do
      {:ok, token} = Invites.create()
      taken = genesis(%{"handle" => "ania"})

      assert build_conn()
             |> put_req_header("x-oktavarium-invite", token)
             |> post(~p"/api/events", Envelope.to_map(taken))
             |> json_response(201)

      {:ok, token2} = Invites.create()
      clash = genesis(%{"handle" => "ania"})

      assert %{"error" => %{"code" => "handle_taken"}} =
               conn
               |> put_req_header("x-oktavarium-invite", token2)
               |> post(~p"/api/events", Envelope.to_map(clash))
               |> json_response(409)

      # zaproszenie nadal działa
      assert build_conn()
             |> put_req_header("x-oktavarium-invite", token2)
             |> post(~p"/api/events", Envelope.to_map(genesis(%{"handle" => "ola"})))
             |> json_response(201)
    end

    test "zdarzenia istniejącej tożsamości nie wymagają zaproszenia", %{conn: conn} do
      Application.put_env(:oktavarium, :registration, :open)
      state = found!()
      Application.put_env(:oktavarium, :registration, :closed)

      envelope =
        Envelope.sign(
          %{
            type: "profile.update",
            seq: 1,
            identity: state.id,
            prev: state.head,
            body: %{"fields" => %{"bio" => "x"}}
          },
          state.founder
        )

      assert conn |> post(~p"/api/events", Envelope.to_map(envelope)) |> json_response(201)
    end
  end

  describe "API tożsamości" do
    test "publiczny stan z głową dziennika, grantami i zasobami", %{conn: conn} do
      state = found!(handle: "pelagia")
      device = keypair()
      state = next!(state, "key.add", %{"key" => key_id(device), "label" => "laptop"})
      {:ok, _} = Blobs.put(@png, "image/png")

      state =
        put_resource(state, "images/a.png", @png, "image/png", %{"meta" => %{"title" => "Kot"}})

      body = conn |> get(~p"/api/identities/pelagia") |> json_response(200)
      assert body["id"] == state.id
      assert body["head"] == %{"seq" => state.seq, "id" => state.head}
      assert [%{"label" => "laptop", "status" => "active"}] = body["members"]

      assert [%{"path" => "images/a.png", "kind" => "image", "meta" => %{"title" => "Kot"}}] =
               body["resources"]

      assert body["founding_key"] == key_id(state.founder)
    end

    test "niepubliczna: tylko dla właściciela po zalogowaniu", %{conn: conn} do
      state = found!(handle: "cicha")
      Repo.update_all(Oktavarium.Identities.Identity, set: [visibility: :restricted])

      assert %{"error" => %{"code" => "unknown_identity"}} =
               conn |> get(~p"/api/identities/cicha") |> json_response(404)

      {session_conn, _csrf, _} = login(build_conn(), state)
      assert %{"id" => id} = session_conn |> get(~p"/api/identities/cicha") |> json_response(200)
      assert id == state.id

      stranger = found!()
      {other_conn, _, _} = login(build_conn(), stranger)
      assert other_conn |> get(~p"/api/identities/cicha") |> json_response(404)
    end
  end

  describe "galeria i strona tożsamości" do
    test "galeria na / pokazuje obrazy i nagrania publicznych tożsamości", %{conn: conn} do
      state = found!(handle: "pelagia")
      {:ok, _} = Blobs.put(@png, "image/png")
      {:ok, _} = Blobs.put(@mp3, "audio/mpeg")

      state =
        put_resource(state, "images/a.png", @png, "image/png", %{
          "meta" => %{"title" => "Kot", "alt" => "Rudy kot"}
        })

      _ =
        put_resource(state, "audio/a.mp3", @mp3, "audio/mpeg", %{"meta" => %{"title" => "Demo"}})

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(src="/blobs/#{hash(@png)}")
      assert html =~ "Rudy kot"
      assert html =~ ~s(src="/blobs/#{hash(@mp3)}")
      assert html =~ "Demo"
      assert html =~ ~s(href="/i/pelagia")
    end

    test "niepubliczne zasoby nie trafiają do galerii", %{conn: conn} do
      state = found!(handle: "cicha")
      {:ok, _} = Blobs.put(@png, "image/png")
      _ = put_resource(state, "images/a.png", @png, "image/png")
      Repo.update_all(Oktavarium.Identities.Identity, set: [visibility: :restricted])
      refute conn |> get(~p"/") |> html_response(200) =~ hash(@png)
    end

    test "strona tożsamości pokazuje zasoby, klucze urządzeń i nowe typy zdarzeń", %{conn: conn} do
      state = found!(handle: "pelagia")
      device = keypair()
      state = next!(state, "key.add", %{"key" => key_id(device), "label" => "laptop"})
      {:ok, _} = Blobs.put(@png, "image/png")
      state = put_resource(state, "images/a.png", @png, "image/png")
      {state, g} = grant!(state, device, "resource.put", "/images/*")
      _ = next!(state, "grant.revoke", %{"grant" => g.id})

      html = conn |> get(~p"/i/pelagia") |> html_response(200)
      assert html =~ "Zasoby"
      assert html =~ "Klucze urządzeń"
      assert html =~ "laptop"
      assert html =~ "Cofnięto uprawnienie"
      assert html =~ "Zapisano zasób"
      assert html =~ "unieważnione"
    end

    test "powłoki aplikacji mają skrypt i CSP bez inline", %{conn: conn} do
      for path <- ["/join", "/login", "/studio"] do
        c = get(conn, path)
        assert html_response(c, 200) =~ ~s(type="module")
        assert [csp] = get_resp_header(c, "content-security-policy")
        refute csp =~ "unsafe-inline"
        assert csp =~ "form-action 'none'"
      end
    end
  end

  describe "subdomeny ze stronami" do
    defp site_conn(handle), do: %{build_conn() | host: handle <> ".sites.test"}

    test "serwuje pliki site/ pod hostem uchwytu, index dla / i katalogów" do
      state = found!(handle: "pelagia")
      html = "<h1>Cześć</h1><link rel=stylesheet href=/css/a.css>"
      css = "h1{color:red}"
      blog = "<p>blog</p>"

      for {b, t} <- [{html, "text/html"}, {css, "text/css"}, {blog, "text/html"}],
          do: {:ok, _} = Blobs.put(b, t)

      state = put_resource(state, "site/index.html", html, "text/html")
      state = put_resource(state, "site/css/a.css", css, "text/css")
      _ = put_resource(state, "site/blog/index.html", blog, "text/html")

      home = get(site_conn("pelagia"), "/")
      assert response(home, 200) == html
      assert get_resp_header(home, "content-type") == ["text/html; charset=utf-8"]
      assert get_resp_header(home, "x-content-type-options") == ["nosniff"]
      assert [csp] = get_resp_header(home, "content-security-policy")
      assert csp =~ "default-src 'self'"
      assert csp =~ "frame-ancestors 'none'"

      assert get(site_conn("pelagia"), "/css/a.css") |> response(200) == css
      assert get(site_conn("pelagia"), "/blog") |> response(200) == blog
      assert get(site_conn("pelagia"), "/index.html") |> response(200) == html
      assert get(site_conn("pelagia"), "/nie-ma.html") |> response(404)
      assert get(site_conn("nikt"), "/") |> response(404)
    end

    test "ETag i 304" do
      state = found!(handle: "pelagia")
      html = "<p>x</p>"
      {:ok, _} = Blobs.put(html, "text/html")
      _ = put_resource(state, "site/index.html", html, "text/html")

      first = get(site_conn("pelagia"), "/")
      [etag] = get_resp_header(first, "etag")

      assert site_conn("pelagia")
             |> put_req_header("if-none-match", etag)
             |> get("/")
             |> response(304)
    end

    test "tylko GET i HEAD, brak ścieżek z .. i brak API na hoście strony" do
      _ = found!(handle: "pelagia")
      assert site_conn("pelagia") |> post("/api/events", %{}) |> response(405)
      assert site_conn("pelagia") |> get("/api/me") |> response(404)
      assert site_conn("pelagia") |> get("/%2e%2e/etc/passwd") |> response(404)
    end

    test "niepubliczna tożsamość nie ma strony" do
      state = found!(handle: "cicha")
      html = "<p>sekret</p>"
      {:ok, _} = Blobs.put(html, "text/html")
      _ = put_resource(state, "site/index.html", html, "text/html")
      Repo.update_all(Oktavarium.Identities.Identity, set: [visibility: :restricted])
      assert site_conn("cicha") |> get("/") |> response(404)
    end

    test "host spoza domeny stron trafia do zwykłej aplikacji", %{conn: conn} do
      assert conn |> get(~p"/") |> html_response(200)

      assert %{conn | host: "pelagia.inna.test"} |> get("/") |> html_response(200) =~
               "Kto tu pracuje"
    end

    test "handle/2 i site_url/1" do
      assert {:ok, "pelagia"} = OktavariumWeb.SitePlug.handle("pelagia.sites.test", "sites.test")
      assert :error = OktavariumWeb.SitePlug.handle("sites.test", "sites.test")
      assert :error = OktavariumWeb.SitePlug.handle("a.b.sites.test", "sites.test")
      assert :error = OktavariumWeb.SitePlug.handle("x_y.sites.test", "sites.test")
      assert OktavariumWeb.SitePlug.site_url("pelagia") =~ ~r{^http://pelagia\.sites\.test}
      assert nil == OktavariumWeb.SitePlug.site_url("a_b")
      assert nil == OktavariumWeb.SitePlug.site_url(nil)
    end
  end
end
