defmodule Oktavarium.CliTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Oktavarium.{Cli, Crypto, Envelope}
  alias Oktavarium.Cli.Keyfile

  @moduletag :tmp_dir

  # pomocnicze

  defp key!(dir, name, kind \\ "signing") do
    path = Path.join(dir, name)
    {:ok, %{id: id}} = Cli.gen_key(kind, path)
    {path, id}
  end

  defp save!(dir, name, envelope) do
    path = Path.join(dir, name)
    :ok = Cli.write_envelope(path, envelope)
    path
  end

  defp genesis!(
         dir,
         key_path,
         name \\ "genesis.json",
         opts \\ [kind: "person", handle: "pelagia"]
       ) do
    {:ok, %{envelope: envelope, event: event}} = Cli.create_identity(key_path, opts)
    {save!(dir, name, envelope), event}
  end

  defp grant!(dir, key_path, after_path, to, name, extra \\ []) do
    opts = [after: after_path, to: to, action: "project.edit"] ++ extra
    {:ok, %{envelope: envelope, event: event}} = Cli.create_grant(key_path, opts)
    {save!(dir, name, envelope), event}
  end

  # --- klucze ---

  describe "gen_key/2 i Keyfile" do
    test "zapisuje klucz z uprawnieniami 0600 i zwraca jego identyfikator", %{tmp_dir: dir} do
      path = Path.join(dir, "k.key")

      assert {:ok, %{id: id, kind: :signing, path: ^path}} = Cli.gen_key("signing", path)
      assert (File.stat!(path).mode &&& 0o777) == 0o600

      assert {:ok, key} = Keyfile.read(path)
      assert key.kind == :signing
      assert Keyfile.id(key) == id
      assert {:ok, _public} = Crypto.decode_key_id(id)
    end

    test "tworzy brakujące katalogi", %{tmp_dir: dir} do
      path = Path.join([dir, "a", "b", "k.key"])
      assert {:ok, _} = Cli.gen_key("auth", path)
      assert {:ok, %{kind: :auth}} = Keyfile.read(path)
    end

    test "nie nadpisuje istniejącego pliku", %{tmp_dir: dir} do
      {path, _id} = key!(dir, "k.key")
      before = File.read!(path)

      assert {:error, {:exists, ^path}} = Cli.gen_key("signing", path)
      assert File.read!(path) == before
    end

    test "wymaga --out i poprawnego rodzaju", %{tmp_dir: dir} do
      assert {:error, {:missing_option, :out}} = Cli.gen_key("signing", nil)

      assert {:error, {:invalid_option, :kind, "admin"}} =
               Cli.gen_key("admin", Path.join(dir, "k.key"))

      refute File.exists?(Path.join(dir, "k.key"))
    end

    test "odczyt: brak pliku, śmieci, niepełny plik", %{tmp_dir: dir} do
      missing = Path.join(dir, "nie-ma.key")
      assert {:error, {:file, ^missing, :enoent}} = Keyfile.read(missing)

      junk = Path.join(dir, "junk.key")
      File.write!(junk, "to nie json")
      assert {:error, :invalid_keyfile} = Keyfile.read(junk)

      partial = Path.join(dir, "partial.key")
      File.write!(partial, ~s({"v": 1}))
      assert {:error, :invalid_keyfile} = Keyfile.read(partial)
    end

    test "odczyt: klucz publiczny niezgodny z prywatnym", %{tmp_dir: dir} do
      {path, _} = key!(dir, "k.key")
      other = Crypto.generate_keypair()

      tampered =
        path
        |> File.read!()
        |> Jason.decode!()
        |> Map.put("public", Crypto.encode(other.public))
        |> Jason.encode!()

      File.write!(path, tampered)
      assert {:error, :key_mismatch} = Keyfile.read(path)
    end

    test "show_key nie ujawnia klucza prywatnego", %{tmp_dir: dir} do
      {path, id} = key!(dir, "k.key", "auth")
      {:ok, key} = Keyfile.read(path)

      assert {:ok, info} = Cli.show_key(path)
      assert info == %{id: id, kind: :auth}
      refute inspect(info) =~ Crypto.encode(key.private)
    end
  end

  # tożsamość

  describe "create_identity/2" do
    test "podpisuje poprawny genesis", %{tmp_dir: dir} do
      {key_path, key_id} = key!(dir, "sign.key")
      {_auth_path, auth_id} = key!(dir, "auth.key", "auth")

      assert {:ok, %{envelope: envelope, event: event}} =
               Cli.create_identity(key_path,
                 kind: "person",
                 handle: "pelagia",
                 auth_keys: [auth_id]
               )

      assert event.genesis?
      assert event.identity == event.id
      assert event.signer == key_id
      assert event.body == %{"kind" => "person", "handle" => "pelagia", "auth_keys" => [auth_id]}
      assert {:ok, ^event} = Envelope.verify(envelope)
    end

    test "obsługuje osobę, kolektyw oraz widoczność bez prywatności", %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")

      assert {:ok, %{event: event}} =
               Cli.create_identity(key_path, kind: "collective", visibility: "unlisted")

      assert event.body == %{"kind" => "collective", "visibility" => "unlisted"}

      assert {:error, {:invalid_option, :visibility, "restricted"}} =
               Cli.create_identity(key_path, kind: "person", visibility: "restricted")

      assert {:error, {:invalid_option, :kind, "project"}} =
               Cli.create_identity(key_path, kind: "project")
    end

    test "handle i auth_keys są opcjonalne i wtedy nie trafiają do ładunku", %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")

      assert {:ok, %{event: event}} = Cli.create_identity(key_path, kind: "collective")
      assert event.body == %{"kind" => "collective"}
    end

    test "wymaga klucza sygnowania, a nie autoryzacji", %{tmp_dir: dir} do
      {auth_path, _} = key!(dir, "auth.key", "auth")

      assert {:error, {:wrong_key_kind, :signing}} =
               Cli.create_identity(auth_path, kind: "person")
    end

    test "odrzuca niepoprawne dane wejściowe", %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")

      assert {:error, {:missing_option, :key}} = Cli.create_identity(nil, kind: "person")
      assert {:error, {:missing_option, :kind}} = Cli.create_identity(key_path, [])

      assert {:error, {:invalid_option, :kind, "bóg"}} =
               Cli.create_identity(key_path, kind: "bóg")

      for handle <- ["A", "x", "Pelagia", "ma spacje", String.duplicate("a", 33)] do
        assert {:error, {:invalid_option, :handle, ^handle}} =
                 Cli.create_identity(key_path, kind: "person", handle: handle)
      end

      assert {:error, {:invalid_key_id, "zly"}} =
               Cli.create_identity(key_path, kind: "person", auth_keys: ["zly"])
    end

    test "deduplikuje klucze autoryzacji", %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")
      {_, auth_id} = key!(dir, "auth.key", "auth")

      assert {:ok, %{event: event}} =
               Cli.create_identity(key_path, kind: "person", auth_keys: [auth_id, auth_id])

      assert event.body["auth_keys"] == [auth_id]
    end
  end

  # granty

  describe "create_grant/2" do
    setup %{tmp_dir: dir} do
      {key_path, key_id} = key!(dir, "sign.key")
      {_, bot_id} = key!(dir, "bot.key")
      {genesis_path, genesis} = genesis!(dir, key_path)

      {:ok,
       key_path: key_path,
       key_id: key_id,
       bot_id: bot_id,
       genesis_path: genesis_path,
       genesis: genesis}
    end

    test "kolejne zdarzenie dziedziczy tożsamość, seq i prev z pliku", ctx do
      %{tmp_dir: dir, key_path: key_path, bot_id: bot_id, genesis_path: gp, genesis: genesis} =
        ctx

      {_path, event} = grant!(dir, key_path, gp, bot_id, "g1.json")

      assert event.type == "grant.create"
      assert event.identity == genesis.id
      assert event.seq == 1
      assert event.prev == genesis.id
      refute event.genesis?

      assert event.body == %{
               "subject" => bot_id,
               "action" => "project.edit",
               "resource" => genesis.id <> "/*"
             }
    end

    test "zasób, okno czasowe i grant nadrzędny trafiają do ładunku", ctx do
      %{tmp_dir: dir, key_path: key_path, bot_id: bot_id, genesis_path: gp, genesis: genesis} =
        ctx

      {pp, parent} = grant!(dir, key_path, gp, bot_id, "parent.json")

      {_path, event} =
        grant!(dir, key_path, pp, bot_id, "child.json",
          resource: genesis.id <> "/lang/pl",
          not_before: "2026-06-01",
          expires_at: "2026-12-01T02:00:00+02:00",
          parent_grant: parent.id
        )

      assert event.body["resource"] == genesis.id <> "/lang/pl"
      assert event.body["not_before"] == DateTime.to_unix(~U[2026-06-01 00:00:00Z])
      assert event.body["expires_at"] == DateTime.to_unix(~U[2026-12-01 00:00:00Z])
      assert event.body["parent_grant"] == parent.id
      assert event.seq == 2
      assert event.prev == parent.id
    end

    test "delegable i parent_grant trafiają do ładunku tylko wtedy, gdy podane", ctx do
      %{tmp_dir: dir, key_path: key_path, bot_id: bot_id, genesis_path: gp} = ctx
      parent_id = Crypto.encode(:crypto.strong_rand_bytes(32))

      {_p, plain} = grant!(dir, key_path, gp, bot_id, "plain.json")
      refute Map.has_key?(plain.body, "delegable")
      refute Map.has_key?(plain.body, "parent_grant")

      {_p, no} = grant!(dir, key_path, gp, bot_id, "no.json", delegable: false)
      refute Map.has_key?(no.body, "delegable")

      {_p, yes} =
        grant!(dir, key_path, gp, bot_id, "yes.json", delegable: true, parent_grant: parent_id)

      assert yes.body["delegable"] == true
      assert yes.body["parent_grant"] == parent_id

      assert {:error, {:invalid_option, :parent_grant, "xyz"}} =
               Cli.create_grant(key_path,
                 after: gp,
                 to: bot_id,
                 action: "a.b",
                 parent_grant: "xyz"
               )
    end

    test "zasób spoza tożsamości jest odrzucany", ctx do
      %{key_path: key_path, bot_id: bot_id, genesis_path: gp, genesis: genesis} = ctx
      base = [after: gp, to: bot_id, action: "project.edit"]

      for resource <- ["inna-tozsamosc/*", "*", "x/" <> genesis.id] do
        assert {:error, {:resource_outside_identity, ^resource, _}} =
                 Cli.create_grant(key_path, base ++ [resource: resource])
      end

      assert {:error, {:invalid_resource, "a//b"}} =
               Cli.create_grant(key_path, base ++ [resource: "a//b"])
    end

    test "niepoprawne dane wejściowe", ctx do
      %{key_path: key_path, bot_id: bot_id, genesis_path: gp} = ctx
      base = [after: gp, to: bot_id, action: "project.edit"]

      assert {:error, {:missing_option, :after}} =
               Cli.create_grant(key_path, Keyword.delete(base, :after))

      assert {:error, {:missing_option, :to}} =
               Cli.create_grant(key_path, Keyword.delete(base, :to))

      assert {:error, {:missing_option, :action}} =
               Cli.create_grant(key_path, Keyword.delete(base, :action))

      assert {:error, {:invalid_key_id, "zly"}} =
               Cli.create_grant(key_path, Keyword.put(base, :to, "zly"))

      assert {:error, {:invalid_action, "pro*ject"}} =
               Cli.create_grant(key_path, Keyword.put(base, :action, "pro*ject"))

      assert {:error, {:invalid_time, :expires_at, "jutro"}} =
               Cli.create_grant(key_path, base ++ [expires_at: "jutro"])

      assert {:error, {:invalid_option, :parent_grant, "xyz"}} =
               Cli.create_grant(key_path, base ++ [parent_grant: "xyz"])
    end

    test "okno czasowe: koniec musi być po początku", ctx do
      %{key_path: key_path, bot_id: bot_id, genesis_path: gp} = ctx
      base = [after: gp, to: bot_id, action: "project.edit"]

      for {nb, ex} <- [{"2026-06-01", "2026-06-01"}, {"2026-06-01", "2026-01-01"}] do
        assert {:error, :invalid_window} =
                 Cli.create_grant(key_path, base ++ [not_before: nb, expires_at: ex])
      end

      assert {:ok, _} = Cli.create_grant(key_path, base ++ [expires_at: "2026-01-01"])
    end

    test "wymaga klucza sygnowania", ctx do
      %{tmp_dir: dir, bot_id: bot_id, genesis_path: gp} = ctx
      {auth_path, _} = key!(dir, "auth.key", "auth")

      assert {:error, {:wrong_key_kind, :signing}} =
               Cli.create_grant(auth_path, after: gp, to: bot_id, action: "project.edit")
    end

    test "odrzuca uszkodzony plik poprzedniego zdarzenia", ctx do
      %{tmp_dir: dir, key_path: key_path, bot_id: bot_id, genesis_path: gp} = ctx

      map = gp |> File.read!() |> Jason.decode!()
      other = Crypto.generate_keypair()
      bad = Path.join(dir, "bad.json")
      File.write!(bad, Jason.encode!(%{map | "signer" => Crypto.key_id(other.public)}))

      assert {:error, {:invalid_envelope, ^bad, :bad_signature}} =
               Cli.create_grant(key_path, after: bad, to: bot_id, action: "project.edit")

      File.write!(bad, "nie json")

      assert {:error, {:invalid_envelope, ^bad, :invalid_json}} =
               Cli.create_grant(key_path, after: bad, to: bot_id, action: "project.edit")

      File.write!(bad, ~s({"payload": 1}))

      assert {:error, {:invalid_envelope, ^bad, :malformed}} =
               Cli.create_grant(key_path, after: bad, to: bot_id, action: "project.edit")
    end
  end

  # weryfikacja plików

  describe "update_profile/2" do
    setup %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")
      {genesis_path, genesis} = genesis!(dir, key_path)
      {:ok, key_path: key_path, genesis_path: genesis_path, genesis: genesis}
    end

    test "zdarzenie dziedziczy tożsamość, seq i prev, a --set i --unset trafiają do fields",
         ctx do
      assert {:ok, %{event: event}} =
               Cli.update_profile(ctx.key_path,
                 after: ctx.genesis_path,
                 set: ["display_name=Pelagia", "bio=a=b, c"],
                 unset: ["location"]
               )

      assert event.type == "profile.update"
      assert event.identity == ctx.genesis.id
      assert event.seq == 1
      assert event.prev == ctx.genesis.id

      assert event.body == %{
               "fields" => %{
                 "display_name" => %{"sha256" => Oktavarium.Content.hash("Pelagia")},
                 "bio" => %{"sha256" => Oktavarium.Content.hash("a=b, c")},
                 "location" => nil
               }
             }
    end

    test "wartość może zawierać znak równości, a pole bez wartości po = jest błędem", ctx do
      assert {:ok, %{event: event}} =
               Cli.update_profile(ctx.key_path,
                 after: ctx.genesis_path,
                 set: ["website=https://a.pl/?x=1"]
               )

      assert event.body["fields"] == %{
               "website" => %{"sha256" => Oktavarium.Content.hash("https://a.pl/?x=1")}
             }

      assert {:error, {:invalid_profile_field, "fields.bio"}} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path, set: ["bio="])
    end

    test "wymaga zmian i nie pozwala na powtórzenia", ctx do
      assert {:error, :no_profile_changes} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path)

      assert {:error, {:duplicate_field, "bio"}} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path, set: ["bio=a", "bio=b"])

      assert {:error, {:duplicate_field, "bio"}} =
               Cli.update_profile(ctx.key_path,
                 after: ctx.genesis_path,
                 set: ["bio=a"],
                 unset: ["bio"]
               )
    end

    test "niepoprawne dane wejściowe", ctx do
      assert {:error, {:invalid_option, :set, "bio"}} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path, set: ["bio"])

      assert {:error, {:invalid_option, :set, "=x"}} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path, set: ["=x"])

      assert {:error, {:invalid_profile_field, "fields.admin"}} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path, set: ["admin=x"])

      assert {:error, {:invalid_profile_field, "fields.admin"}} =
               Cli.update_profile(ctx.key_path, after: ctx.genesis_path, unset: ["admin"])

      assert {:error, {:invalid_profile_field, "fields.website"}} =
               Cli.update_profile(ctx.key_path,
                 after: ctx.genesis_path,
                 set: ["website=nie-adres"]
               )

      assert {:error, {:missing_option, :after}} =
               Cli.update_profile(ctx.key_path, set: ["bio=x"])

      assert {:error, {:missing_option, :key}} =
               Cli.update_profile(nil, after: ctx.genesis_path, set: ["bio=x"])
    end

    test "wymaga klucza sygnowania", %{tmp_dir: dir} = ctx do
      {auth_path, _} = key!(dir, "auth.key", "auth")

      assert {:error, {:wrong_key_kind, :signing}} =
               Cli.update_profile(auth_path, after: ctx.genesis_path, set: ["bio=x"])
    end

    test "komunikaty o błędach profilu są czytelne" do
      assert Cli.format_error(:no_profile_changes) =~ "--set"
      assert Cli.format_error({:duplicate_field, "bio"}) =~ "bio"
      assert Cli.format_error({:invalid_profile_field, "fields.admin"}) =~ "admin"
      assert Cli.format_error({:invalid_profile_field, "fields.admin"}) =~ "display_name"
      assert Cli.format_error({:invalid_profile_field, "fields"}) =~ "profilu"
    end
  end

  describe "submit/3" do
    setup %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")
      {genesis_path, genesis} = genesis!(dir, key_path)
      {:ok, %{event: e1}} = Cli.update_profile(key_path, after: genesis_path, set: ["bio=x"])
      {:ok, key_path: key_path, genesis_path: genesis_path, genesis: genesis, e1: e1}
    end

    # transport, który zapamiętuje żądania i odpowiada według skryptu
    defp fake_post(responses) do
      {:ok, agent} = Agent.start_link(fn -> {responses, []} end)

      post = fn url, json ->
        Agent.get_and_update(agent, fn {[response | rest], calls} ->
          {response, {rest, [{url, json} | calls]}}
        end)
      end

      {post, fn -> agent |> Agent.get(fn {_, calls} -> Enum.reverse(calls) end) end}
    end

    defp created(id, identity, seq),
      do: {:ok, 201, Jason.encode!(%{id: id, identity: identity, seq: seq, type: "x"})}

    test "wysyła koperty po kolei na /api/events", ctx do
      %{tmp_dir: dir, genesis_path: gp, genesis: g} = ctx

      {:ok, %{envelope: env, event: e1}} =
        Cli.update_profile(ctx.key_path, after: gp, set: ["bio=x"])

      p1 = save!(dir, "p1.json", env)

      {post, calls} = fake_post([created(g.id, g.id, 0), created(e1.id, g.id, 1)])

      assert {:ok, [first, second]} = Cli.submit([gp, p1], "http://localhost:4000/", post: post)
      assert %{path: ^gp, id: id0, identity: identity, seq: 0} = first
      assert id0 == g.id and identity == g.id
      assert %{path: ^p1, seq: 1} = second

      assert [{url0, json0}, {url1, _}] = calls.()
      assert url0 == "http://localhost:4000/api/events"
      assert url1 == url0
      assert {:ok, envelope} = json0 |> Jason.decode!() |> Envelope.from_map()
      assert {:ok, %{genesis?: true}} = Envelope.verify(envelope)
    end

    test "zatrzymuje się na pierwszym błędzie i podaje kod serwera", ctx do
      %{tmp_dir: dir, genesis_path: gp, genesis: g} = ctx
      {:ok, %{envelope: env}} = Cli.update_profile(ctx.key_path, after: gp, set: ["bio=x"])
      p1 = save!(dir, "p1.json", env)

      rejected = {:ok, 409, Jason.encode!(%{error: %{code: "bad_seq", expected_seq: 4}})}
      {post, calls} = fake_post([rejected, created(g.id, g.id, 0)])

      assert {:error, {:submit_failed, ^gp, 409, "bad_seq (expected_seq=4)"}} =
               Cli.submit([gp, p1], "http://x", post: post)

      assert length(calls.()) == 1

      message = Cli.format_error({:submit_failed, gp, 409, "bad_seq (expected_seq=4)"})
      assert message =~ "HTTP 409"
      assert message =~ "bad_seq"
    end

    test "serwer niedostępny, odpowiedź bez kodu i brak plików", ctx do
      %{genesis_path: gp} = ctx

      assert {:error, {:unreachable, "http://x/api/events", :econnrefused}} =
               Cli.submit([gp], "http://x", post: fn _, _ -> {:error, :econnrefused} end)

      assert Cli.format_error({:unreachable, "http://x/api/events", :econnrefused}) =~
               "econnrefused"

      assert {:error, {:submit_failed, ^gp, 502, "odpowiedź bez kodu błędu"}} =
               Cli.submit([gp], "http://x", post: fn _, _ -> {:ok, 502, "<html>"} end)

      assert {:error, {:submit_failed, ^gp, 201, _}} =
               Cli.submit([gp], "http://x", post: fn _, _ -> {:ok, 201, "nie json"} end)

      assert {:error, :no_files} = Cli.submit([], "http://x", [])
    end

    test "nieczytelny plik nie jest wysyłany", %{tmp_dir: dir} do
      bad = Path.join(dir, "bad.json")
      File.write!(bad, "to nie json")
      post = fn _, _ -> flunk("nie powinno być żądania") end

      assert {:error, {:invalid_envelope, ^bad, :invalid_json}} =
               Cli.submit([bad], "http://x", post: post)

      assert {:error, {:file, _, :enoent}} =
               Cli.submit([Path.join(dir, "brak.json")], "http://x", post: post)
    end
  end

  describe "verify_files/1" do
    setup %{tmp_dir: dir} do
      {key_path, _} = key!(dir, "sign.key")
      {_, bot_id} = key!(dir, "bot.key")
      {gp, genesis} = genesis!(dir, key_path)
      {p1, e1} = grant!(dir, key_path, gp, bot_id, "g1.json")
      {p2, e2} = grant!(dir, key_path, p1, bot_id, "g2.json")

      {:ok,
       key_path: key_path,
       bot_id: bot_id,
       genesis_path: gp,
       genesis: genesis,
       p1: p1,
       e1: e1,
       p2: p2,
       e2: e2}
    end

    test "poprawny łańcuch", ctx do
      assert {:ok, events} = Cli.verify_files([ctx.genesis_path, ctx.p1, ctx.p2])
      assert Enum.map(events, & &1.seq) == [0, 1, 2]
      assert Enum.map(events, & &1.id) == [ctx.genesis.id, ctx.e1.id, ctx.e2.id]
    end

    test "pojedynczy plik, także w środku łańcucha", ctx do
      assert {:ok, [_]} = Cli.verify_files([ctx.genesis_path])
      assert {:ok, [_]} = Cli.verify_files([ctx.p2])
    end

    test "brak plików", _ctx do
      assert {:error, :no_files} = Cli.verify_files([])
    end

    test "luka w seq", ctx do
      assert {:error, {:broken_chain, p2, :seq_gap}} =
               Cli.verify_files([ctx.genesis_path, ctx.p2])

      assert p2 == ctx.p2
    end

    test "zła kolejność i genesis w środku", ctx do
      assert {:error, {:broken_chain, _, :seq_gap}} = Cli.verify_files([ctx.p1, ctx.p2, ctx.p1])

      assert {:error, {:broken_chain, path, :unexpected_genesis}} =
               Cli.verify_files([ctx.p1, ctx.genesis_path])

      assert path == ctx.genesis_path
    end

    test "zdarzenia różnych tożsamości", %{tmp_dir: dir} = ctx do
      {other_key, _} = key!(dir, "other.key")
      {other_genesis, _} = genesis!(dir, other_key, "other-genesis.json", kind: "collective")
      {other_grant, _} = grant!(dir, other_key, other_genesis, ctx.bot_id, "other-g1.json")

      assert {:error, {:broken_chain, ^other_grant, :identity_mismatch}} =
               Cli.verify_files([ctx.genesis_path, other_grant])
    end

    test "ten sam seq, ale inny poprzednik", %{tmp_dir: dir} = ctx do
      # alternatywne zdarzenie seq=1 po tym samym genesis (rozwidlenie)
      {fork, fork_event} =
        grant!(dir, ctx.key_path, ctx.genesis_path, ctx.bot_id, "fork.json",
          resource: ctx.genesis.id <> "/x"
        )

      assert fork_event.seq == 1

      # [genesis, g1, fork]: fork ma seq 1, a oczekiwano 2
      assert {:error, {:broken_chain, ^fork, :seq_gap}} =
               Cli.verify_files([ctx.genesis_path, ctx.p1, fork])
    end

    test "uszkodzona koperta", %{tmp_dir: dir} = ctx do
      map = ctx.p1 |> File.read!() |> Jason.decode!()
      other = Crypto.generate_keypair()
      bad = Path.join(dir, "bad.json")

      File.write!(
        bad,
        Jason.encode!(%{
          map
          | "signature" => Crypto.encode(Crypto.sign(:event, "x", other.private))
        })
      )

      assert {:error, {:invalid_envelope, ^bad, :bad_signature}} =
               Cli.verify_files([ctx.genesis_path, bad])
    end

    test "brakujący plik", ctx do
      missing = Path.join(Path.dirname(ctx.genesis_path), "nie-ma.json")
      assert {:error, {:file, ^missing, :enoent}} = Cli.verify_files([missing])
    end
  end

  # argumenty i komunikaty

  describe "parse_args/3" do
    test "ścisłe opcje i powtarzalne --auth-key" do
      switches = [kind: :string, auth_key: [:string, :keep]]

      assert {:ok, opts, []} =
               Cli.parse_args(
                 ["--kind", "person", "--auth-key", "a", "--auth-key", "b"],
                 switches
               )

      assert opts[:kind] == "person"
      assert Keyword.get_values(opts, :auth_key) == ["a", "b"]
    end

    test "wartość zaczynająca się od myślnika nie jest brana za opcję" do
      # base64url: pierwszy bajt 0xFB daje identyfikator zaczynający się od "-"
      dash_id = Crypto.encode(<<0xFB, 0::size(248)>>)
      assert String.starts_with?(dash_id, "-")
      double_dash_id = Crypto.encode(<<0xFB, 0xEF, 0::size(240)>>)
      assert String.starts_with?(double_dash_id, "--")

      switches = [to: :string, action: :string, auth_key: [:string, :keep]]

      assert {:ok, opts, []} = Cli.parse_args(["--to", dash_id, "--action", "a.b"], switches)
      assert opts == [to: dash_id, action: "a.b"]

      assert {:ok, opts, []} =
               Cli.parse_args(["--auth-key", dash_id, "--auth-key", double_dash_id], switches)

      assert Keyword.get_values(opts, :auth_key) == [dash_id, double_dash_id]

      # już sklejona postać też działa
      assert {:ok, [to: ^dash_id], []} = Cli.parse_args(["--to=" <> dash_id], switches)
    end

    test "opcja bez wartości przed kolejną znaną opcją nadal jest błędem" do
      switches = [to: :string, action: :string]

      assert {:error, {:unknown_option, "--to"}} =
               Cli.parse_args(["--to", "--action", "a.b"], switches)
    end

    test "nieznana opcja i argumenty pozycyjne" do
      assert {:error, {:unknown_option, "--nope"}} = Cli.parse_args(["--nope"], kind: :string)
      assert {:error, {:unexpected_args, ["x"]}} = Cli.parse_args(["x"], kind: :string)
      assert {:ok, [], ["x", "y"]} = Cli.parse_args(["x", "y"], [], allow_args: true)
    end
  end

  describe "parse_args/3 dla profilu" do
    test "powtarzalne --set i --unset" do
      switches = [set: [:string, :keep], unset: [:string, :keep]]

      assert {:ok, opts, []} =
               Cli.parse_args(
                 ["--set", "a=1", "--unset", "b", "--set", "c=-2", "--unset", "-d"],
                 switches
               )

      assert Keyword.get_values(opts, :set) == ["a=1", "c=-2"]
      assert Keyword.get_values(opts, :unset) == ["b", "-d"]
    end
  end

  describe "format_error/1" do
    test "najczęstsze błędy mają czytelne komunikaty" do
      assert Cli.format_error({:exists, "k.key"}) =~ "już istnieje"
      assert Cli.format_error({:missing_option, :not_before}) =~ "--not-before"
      assert Cli.format_error({:file, "x.json", :enoent}) =~ "no such file"
      assert Cli.format_error({:broken_chain, "x.json", :seq_gap}) =~ "seq_gap"
      assert Cli.format_error(:coś_nieznanego) =~ "coś_nieznanego"
    end
  end
end
