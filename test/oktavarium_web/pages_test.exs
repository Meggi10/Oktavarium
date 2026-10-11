defmodule OktavariumWeb.PagesTest do
  use OktavariumWeb.ConnCase

  import Oktavarium.Fixtures

  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Log.Event

  defp html(conn, status \\ 200), do: html_response(conn, status)

  defp profile!(state, fields), do: next!(state, "profile.update", %{"fields" => fields})

  describe "strona główna" do
    test "pusta lista pokazuje, jak zacząć", %{conn: conn} do
      body = conn |> get(~p"/") |> html()
      assert body =~ "Kto tu pracuje"
      assert body =~ "Nie ma jeszcze żadnych tożsamości"
      assert body =~ "mix oktavarium.identity.create"
      refute body =~ ~s(class="directory")
    end

    test "lista tożsamości z nazwą, uchwytem, rodzajem i liczbą zdarzeń", %{conn: conn} do
      pelagia =
        found!(handle: "pelagia")
        |> profile!(%{"display_name" => "Pelagia", "bio" => "Rysuję\ni piszę kod."})

      found!(handle: "druk", kind: "project")

      body = conn |> get(~p"/") |> html()
      assert body =~ ~s(class="directory")
      assert body =~ "Pelagia"
      assert body =~ "@pelagia"
      assert body =~ "Rysuję i piszę kod."
      assert body =~ "użytkownik"
      assert body =~ "projekt"
      assert body =~ "2 zdarzenia"
      assert body =~ "1 zdarzenie"
      assert body =~ ~s(href="/i/pelagia")
      assert body =~ ~s(href="/i/druk")
      assert body =~ String.slice(pelagia.head, 0, 6)
      refute body =~ "Nie ma jeszcze żadnych tożsamości"
    end

    test "tożsamość bez uchwytu linkuje po id", %{conn: conn} do
      state = found!()
      body = conn |> get(~p"/") |> html()
      assert body =~ ~s(href="/i/#{state.id}")
    end

    test "nagłówki bezpieczeństwa i zasoby statyczne", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'self'"
      assert csp =~ "frame-ancestors 'none'"

      assert build_conn() |> get("/assets/app.css") |> response(200) =~ "--paper"
      assert build_conn() |> get("/favicon.svg") |> response(200) =~ "<svg"
    end

    test "nieznana strona to polski 404", %{conn: conn} do
      body = conn |> get("/nie-ma") |> html(404)
      assert body =~ "Nie ma takiej strony"
    end
  end

  describe "strona tożsamości" do
    setup do
      pelagia = found!(handle: "pelagia")
      bot = found!(handle: "pelagia-bot")

      pelagia =
        profile!(pelagia, %{
          "display_name" => "Pelagia",
          "bio" => "Rysuję i piszę kod.",
          "location" => "Warszawa",
          "website" => "https://example.org/pelagia"
        })

      {pelagia, grant} =
        grant!(pelagia, bot.founder, "profile.update", "/profile/bio", %{"delegable" => true})

      pelagia = profile!(pelagia, %{"location" => nil})
      {:ok, pelagia: pelagia, bot: bot, grant: grant}
    end

    test "profil, tabliczka z danymi i zweryfikowany dziennik", %{conn: conn, pelagia: pelagia} do
      body = conn |> get(~p"/i/pelagia") |> html()

      assert body =~ "<h1>Pelagia</h1>"
      assert body =~ "@pelagia"
      assert body =~ "Rysuję i piszę kod."
      assert body =~ ~s(href="https://example.org/pelagia")
      assert body =~ ~s(rel="nofollow noopener noreferrer ugc")
      assert body =~ pelagia.id
      assert body =~ "Zweryfikowany: podpisy i łańcuch zdarzeń się zgadzają."
      assert body =~ ~s(href="/api/identities/#{pelagia.id}/events")
      assert body =~ "Klucz założycielski"
      assert body =~ "Klucze autoryzacji"
      refute body =~ ~s(role="alert")
    end

    test "uprawnienia: komu, co, gdzie i w jakim stanie", %{conn: conn} do
      body = conn |> get(~p"/i/pelagia") |> html()

      assert body =~ "Uprawnienia"
      assert body =~ ~s(<a class="holder" href="/i/pelagia-bot">@pelagia-bot</a>)
      assert body =~ "profile.update"
      assert body =~ "/profile/bio"
      assert body =~ "może przekazywać dalej"
      assert body =~ "aktywne"
    end

    test "uprawnienie unieważnione ma odpowiedni stan", %{conn: conn, grant: grant} do
      Repo.get!(Grant, grant.id)
      |> Ecto.Changeset.change(revoked_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      body = conn |> get(~p"/i/pelagia") |> html()
      assert body =~ "unieważnione"
      refute body =~ ">aktywne<"
    end

    test "dziennik: zdarzenia od najnowszego, z opisem zmian", %{conn: conn} do
      body = conn |> get(~p"/i/pelagia") |> html()

      assert body =~ "Założono tożsamość"
      assert body =~ "Nadano uprawnienie"
      assert body =~ "Zmieniono profil"
      assert body =~ "usunięto"
      assert body =~ "Miejsce"
      assert body =~ "Opis"

      positions =
        for t <- ["#3", "#2", "#1", "#0"],
            do: :binary.match(body, ~s(<span class="ev-seq">) <> t) |> elem(0)

      assert positions == Enum.sort(positions)
    end

    test "id tożsamości z uchwytem przekierowuje na adres z uchwytem", %{
      conn: conn,
      pelagia: pelagia
    } do
      conn = get(conn, ~p"/i/#{pelagia.id}")
      assert redirected_to(conn) == "/i/pelagia"

      conn = get(build_conn(), ~p"/i/#{pelagia.id}?before=2")
      assert redirected_to(conn) == "/i/pelagia?before=2"
    end

    test "tożsamość bez uchwytu otwiera się pod id", %{conn: conn} do
      state = found!() |> profile!(%{"bio" => "bez uchwytu"})
      body = conn |> get(~p"/i/#{state.id}") |> html()
      assert body =~ "bez uchwytu"
    end

    test "nieznana albo ukryta tożsamość to 404", %{conn: conn, pelagia: pelagia} do
      assert_error_sent 404, fn -> get(conn, ~p"/i/nie-ma") end

      Repo.get!(Identity, pelagia.id)
      |> Ecto.Changeset.change(visibility: :restricted)
      |> Repo.update!()

      assert_error_sent 404, fn -> get(build_conn(), ~p"/i/pelagia") end
    end

    test "treść od użytkowników jest escapowana", %{conn: conn} do
      state =
        found!(handle: "xss")
        |> profile!(%{"display_name" => "<b>Hej</b>", "bio" => "<script>alert(1)</script>"})

      body = conn |> get(~p"/i/xss") |> html()

      refute body =~ "<script>alert"
      refute body =~ "<b>Hej</b>"
      assert body =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      assert body =~ "&lt;b&gt;Hej&lt;/b&gt;"
      assert state.seq == 1
    end

    test "uszkodzony dziennik jest widoczny na stronie", %{conn: conn, pelagia: pelagia} do
      import Ecto.Query

      from(e in Event, where: e.identity_id == ^pelagia.id and e.seq == 1)
      |> Repo.update_all(set: [signature: :binary.copy(<<0>>, 64)])

      body = conn |> get(~p"/i/pelagia") |> html()
      assert body =~ ~s(role="alert")
      assert body =~ "Uszkodzony od zdarzenia #1"
      assert body =~ "Zdarzenie nie przechodzi weryfikacji"
      refute body =~ "Zweryfikowany: podpisy"
    end

    test "tożsamość bez opisu i bez uprawnień", %{conn: conn} do
      found!(handle: "pusta")
      body = conn |> get(~p"/i/pusta") |> html()
      assert body =~ "Ta tożsamość nie ma jeszcze opisu."
      assert body =~ "Nikomu nie nadano uprawnień."
    end
  end

  describe "strony dziennika" do
    test "starsze zdarzenia są dostępne przez ?before", %{conn: conn} do
      state =
        Enum.reduce(1..55, found!(handle: "dluga"), fn n, acc ->
          profile!(acc, %{"bio" => "wersja #{n}"})
        end)

      first = conn |> get(~p"/i/dluga") |> html()
      assert first =~ "Starsze zdarzenia"
      assert first =~ ~s(href="/i/dluga?before=6")
      assert first =~ ~s(<span class="ev-seq">#55)
      refute first =~ ~s(<span class="ev-seq">#5<)

      second = build_conn() |> get("/i/dluga?before=6") |> html()
      assert second =~ ~s(<span class="ev-seq">#5<)
      assert second =~ ~s(<span class="ev-seq">#0<)
      assert second =~ "Wróć do najnowszych zdarzeń"
      refute second =~ "Starsze zdarzenia"
      assert state.seq == 55
    end

    test "zły parametr before jest ignorowany", %{conn: conn} do
      found!(handle: "alfa")

      for bad <- ["abc", "-3", "0", "1.5"],
          do: assert(conn |> get("/i/alfa?before=#{bad}") |> html() =~ "Założono tożsamość")
    end
  end
end
