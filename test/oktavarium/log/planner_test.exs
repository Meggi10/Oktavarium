defmodule Oktavarium.Log.PlannerTest do
  use ExUnit.Case, async: true

  alias Oktavarium.{Crypto, Envelope}
  alias Oktavarium.Log.{Facts, Planner}

  defp kp, do: Crypto.generate_keypair()
  defp id(keypair), do: Crypto.key_id(keypair.public)

  defp verified(envelope) do
    {:ok, event} = Envelope.verify(envelope)
    {envelope, event}
  end

  defp kinds(ops), do: Enum.map(ops, &elem(&1, 0))
  defp op(ops, kind), do: ops |> Enum.filter(&(elem(&1, 0) == kind)) |> Enum.map(&elem(&1, 1))

  @active_signing %{kind: :signing, status: :active}
  @active_auth %{kind: :auth, status: :active}

  # genesis

  describe "identity.genesis" do
    setup do
      founder = kp()
      auth = kp()
      body = %{"kind" => "user", "handle" => "pelagia", "auth_keys" => [id(auth)]}
      {envelope, event} = founder |> then(&Envelope.genesis(body, &1)) |> verified()
      {:ok, founder: founder, auth: auth, body: body, envelope: envelope, event: event}
    end

    defp genesis_with(ctx, body_changes) do
      body = Map.merge(ctx.body, body_changes)
      {envelope, event} = ctx.founder |> then(&Envelope.genesis(body, &1)) |> verified()
      {envelope, event}
    end

    defp genesis_without(ctx, key) do
      body = Map.delete(ctx.body, key)
      ctx.founder |> then(&Envelope.genesis(body, &1)) |> verified()
    end

    test "poprawny genesis daje operacje w kolejności zgodnej z kluczami obcymi", ctx do
      assert {:ok, ops} = Planner.plan(ctx.envelope, ctx.event, %Facts{})
      assert kinds(ops) == [:identity, :key, :key, :event, :auth_link]

      assert [identity] = op(ops, :identity)
      assert identity.id == ctx.event.id
      assert identity.kind == :user
      assert identity.handle == "pelagia"
      assert identity.parent_id == nil

      [signing, auth] = op(ops, :key)
      assert signing.id == id(ctx.founder)
      assert signing.kind == :signing
      assert signing.home_identity_id == ctx.event.id
      assert signing.public_key == ctx.founder.public
      assert auth.id == id(ctx.auth)
      assert auth.kind == :auth
      assert auth.home_identity_id == nil
      assert auth.public_key == ctx.auth.public

      assert [event] = op(ops, :event)
      assert event.id == ctx.event.id
      assert event.identity_id == ctx.event.id
      assert event.seq == 0
      assert event.prev == nil
      assert event.payload == ctx.envelope.payload
      assert event.signature == ctx.envelope.signature
      assert event.signer_key_id == id(ctx.founder)

      assert [link] = op(ops, :auth_link)

      assert link == %{
               identity_id: ctx.event.id,
               key_id: id(ctx.auth),
               status: :active,
               added_event_id: ctx.event.id
             }
    end

    test "handle jest opcjonalny", ctx do
      {envelope, event} = genesis_without(ctx, "handle")
      assert {:ok, ops} = Planner.plan(envelope, event, %Facts{})
      assert [%{handle: nil}] = op(ops, :identity)
    end

    test "istniejący klucz autoryzacji jest współdzielony, a nie tworzony ponownie", ctx do
      facts = %Facts{keys: %{id(ctx.auth) => @active_auth}}

      assert {:ok, ops} = Planner.plan(ctx.envelope, ctx.event, facts)
      assert kinds(ops) == [:identity, :key, :event, :auth_link]
    end

    test "powtórzone identyfikatory kluczy autoryzacji są scalane", ctx do
      {envelope, event} = genesis_with(ctx, %{"auth_keys" => [id(ctx.auth), id(ctx.auth)]})
      assert {:ok, ops} = Planner.plan(envelope, event, %Facts{})
      assert length(op(ops, :auth_link)) == 1
    end

    test "wiele kluczy autoryzacji", ctx do
      second = kp()
      {envelope, event} = genesis_with(ctx, %{"auth_keys" => [id(ctx.auth), id(second)]})

      assert {:ok, ops} = Planner.plan(envelope, event, %Facts{})
      assert length(op(ops, :auth_link)) == 2
      assert length(op(ops, :key)) == 3
    end

    test "powtórzone zdarzenie", ctx do
      assert {:error, :duplicate_event} =
               Planner.plan(ctx.envelope, ctx.event, %Facts{event_exists?: true})
    end

    test "wymaga co najmniej jednego klucza autoryzacji", ctx do
      {e, ev} = genesis_without(ctx, "auth_keys")
      assert {:error, :auth_key_required} = Planner.plan(e, ev, %Facts{})

      {e, ev} = genesis_with(ctx, %{"auth_keys" => []})
      assert {:error, :auth_key_required} = Planner.plan(e, ev, %Facts{})
    end

    test "niepoprawne auth_keys", ctx do
      for bad <- ["tekst", 5, %{}, ["krótki"], [5], [nil], [id(ctx.auth), "!!!"]] do
        {e, ev} = genesis_with(ctx, %{"auth_keys" => bad})

        assert {:error, {:invalid_body, "auth_keys"}} = Planner.plan(e, ev, %Facts{}),
               inspect(bad)
      end
    end

    test "niepoprawny rodzaj", ctx do
      for bad <- ["admin", "", 5, nil, ["user"]] do
        {e, ev} = genesis_with(ctx, %{"kind" => bad})
        assert {:error, {:invalid_body, "kind"}} = Planner.plan(e, ev, %Facts{}), inspect(bad)
      end

      {e, ev} = genesis_without(ctx, "kind")
      assert {:error, {:invalid_body, "kind"}} = Planner.plan(e, ev, %Facts{})
    end

    test "niepoprawny handle", ctx do
      for bad <- ["A", "x", "Pelagia", "ma spacje", 5, ["pelagia"]] do
        {e, ev} = genesis_with(ctx, %{"handle" => bad})
        assert {:error, {:invalid_body, "handle"}} = Planner.plan(e, ev, %Facts{}), inspect(bad)
      end
    end

    test "klucz sygnowania może założyć tylko jedną tożsamość", ctx do
      facts = %Facts{signer_key: @active_signing}

      assert {:error, :signing_key_already_registered} =
               Planner.plan(ctx.envelope, ctx.event, facts)
    end

    test "ten sam klucz nie może być jednocześnie sygnowania i autoryzacji", ctx do
      {e, ev} = genesis_with(ctx, %{"auth_keys" => [id(ctx.founder)]})
      assert {:error, {:key_kind_conflict, key}} = Planner.plan(e, ev, %Facts{})
      assert key == id(ctx.founder)

      facts = %Facts{keys: %{id(ctx.auth) => @active_signing}}
      assert {:error, {:key_kind_conflict, key}} = Planner.plan(ctx.envelope, ctx.event, facts)
      assert key == id(ctx.auth)
    end

    test "unieważniony klucz autoryzacji", ctx do
      facts = %Facts{keys: %{id(ctx.auth) => %{kind: :auth, status: :revoked}}}
      assert {:error, {:key_revoked, key}} = Planner.plan(ctx.envelope, ctx.event, facts)
      assert key == id(ctx.auth)
    end

    test "zajęty handle", ctx do
      assert {:error, :handle_taken} =
               Planner.plan(ctx.envelope, ctx.event, %Facts{handle_taken?: true})
    end
  end

  # zdarzenia zwykłe

  describe "łańcuch i podpisujący" do
    setup do
      founder = kp()
      bot = kp()

      {_g, genesis} =
        founder
        |> then(&Envelope.genesis(%{"kind" => "user", "auth_keys" => [id(kp())]}, &1))
        |> verified()

      facts = %Facts{
        identity: %{id: genesis.id},
        head: %{seq: 0, id: genesis.id},
        founding_key_id: id(founder),
        signer_key: @active_signing,
        subject_key: @active_signing
      }

      {:ok, founder: founder, bot: bot, genesis: genesis, facts: facts}
    end

    defp grant_body(ctx, changes) do
      Map.merge(
        %{
          "subject" => id(ctx.bot),
          "action" => "project.edit",
          "resource" => ctx.genesis.id <> "/*"
        },
        changes
      )
    end

    defp grant(ctx, changes \\ %{}, opts \\ []) do
      %{
        type: Keyword.get(opts, :type, "grant.create"),
        seq: Keyword.get(opts, :seq, 1),
        identity: Keyword.get(opts, :identity, ctx.genesis.id),
        prev: Keyword.get(opts, :prev, ctx.genesis.id),
        body: grant_body(ctx, changes)
      }
      |> Envelope.sign(Keyword.get(opts, :signer, ctx.founder))
      |> verified()
    end

    test "poprawny grant", ctx do
      {envelope, event} = grant(ctx)

      assert {:ok, ops} = Planner.plan(envelope, event, ctx.facts)
      assert kinds(ops) == [:event, :grant]

      assert [grant] = op(ops, :grant)
      assert grant.id == event.id
      assert grant.identity_id == ctx.genesis.id
      assert grant.issuer_key_id == id(ctx.founder)
      assert grant.subject_key_id == id(ctx.bot)
      assert grant.action == "project.edit"
      assert grant.resource == ctx.genesis.id <> "/*"
      assert grant.not_before == nil
      assert grant.expires_at == nil
      assert grant.parent_grant_id == nil

      assert [%{seq: 1, prev: prev}] = op(ops, :event)
      assert prev == ctx.genesis.id
    end

    test "okno czasowe jest zamieniane na daty", ctx do
      nb = DateTime.to_unix(~U[2026-06-01 00:00:00Z])
      ex = DateTime.to_unix(~U[2099-01-01 00:00:00Z])
      {envelope, event} = grant(ctx, %{"not_before" => nb, "expires_at" => ex})

      assert {:ok, ops} = Planner.plan(envelope, event, ctx.facts)
      assert [%{not_before: not_before, expires_at: expires_at}] = op(ops, :grant)
      assert DateTime.compare(not_before, ~U[2026-06-01 00:00:00Z]) == :eq
      assert DateTime.compare(expires_at, ~U[2099-01-01 00:00:00Z]) == :eq
    end

    test "niepoprawne okno czasowe", ctx do
      t = DateTime.to_unix(~U[2026-06-01 00:00:00Z])

      {e, ev} = grant(ctx, %{"not_before" => t, "expires_at" => t})
      assert {:error, :invalid_window} = Planner.plan(e, ev, ctx.facts)

      {e, ev} = grant(ctx, %{"not_before" => t, "expires_at" => t - 1})
      assert {:error, :invalid_window} = Planner.plan(e, ev, ctx.facts)

      for {field, bad} <- [{"not_before", "jutro"}, {"expires_at", 1.5}, {"expires_at", 10 ** 30}] do
        {e, ev} = grant(ctx, %{field => bad})

        assert {:error, {:invalid_body, ^field}} = Planner.plan(e, ev, ctx.facts),
               inspect({field, bad})
      end
    end

    test "niepoprawne pola grantu", ctx do
      for {field, bad} <- [
            {"subject", "krótki"},
            {"subject", 5},
            {"subject", nil},
            {"action", "pro*ject"},
            {"action", 5},
            {"action", nil},
            {"resource", "inna-tozsamosc/*"},
            {"resource", "*"},
            {"resource", "a//b"},
            {"resource", nil}
          ] do
        {e, ev} = grant(ctx, %{field => bad})

        assert {:error, {:invalid_body, ^field}} = Planner.plan(e, ev, ctx.facts),
               inspect({field, bad})
      end
    end

    test "delegable trafia do grantu, a niepoprawna wartość jest odrzucana", ctx do
      {e, ev} = grant(ctx, %{"delegable" => true})
      assert {:ok, ops} = Planner.plan(e, ev, ctx.facts)
      assert [%{delegable: true}] = op(ops, :grant)

      {e, ev} = grant(ctx)
      assert {:ok, ops} = Planner.plan(e, ev, ctx.facts)
      assert [%{delegable: false}] = op(ops, :grant)

      for bad <- ["tak", 1, [true]] do
        {e, ev} = grant(ctx, %{"delegable" => bad})

        assert {:error, {:invalid_body, "delegable"}} = Planner.plan(e, ev, ctx.facts),
               inspect(bad)
      end
    end

    test "niepoprawny identyfikator grantu nadrzędnego", ctx do
      for bad <- ["krótki", 5, ["x"]] do
        {e, ev} = grant(ctx, %{"parent_grant" => bad})

        assert {:error, {:invalid_body, "parent_grant"}} = Planner.plan(e, ev, ctx.facts),
               inspect(bad)
      end
    end

    test "klucz założycielski nie podaje grantu nadrzędnego", ctx do
      {e, ev} = grant(ctx, %{"parent_grant" => ctx.genesis.id})
      assert {:error, :unexpected_parent_grant} = Planner.plan(e, ev, ctx.facts)
    end

    test "delegowanie przez klucz, który ma delegable grant", ctx do
      parent_id = Crypto.encode(:crypto.strong_rand_bytes(32))

      parent = %{
        id: parent_id,
        issuer_key_id: id(ctx.founder),
        subject_key_id: id(ctx.bot),
        parent_grant_id: nil,
        action: "project.*",
        resource: ctx.genesis.id <> "/*",
        not_before: nil,
        expires_at: nil,
        revoked_at: nil,
        delegable: true
      }

      facts = %{ctx.facts | grants: [parent], now: ~U[2026-10-06 12:00:00Z]}
      subject = kp()

      {e, ev} =
        grant(ctx, %{"subject" => id(subject), "parent_grant" => parent_id, "delegable" => true},
          signer: ctx.bot
        )

      assert {:ok, ops} = Planner.plan(e, ev, facts)

      assert [%{parent_grant_id: ^parent_id, issuer_key_id: issuer, delegable: true}] =
               op(ops, :grant)

      assert issuer == id(ctx.bot)

      # to samo bez delegowania: grant nadrzędny nieznany
      assert {:error, :unknown_parent_grant} = Planner.plan(e, ev, %{facts | grants: []})

      # poza zakresem rodzica
      {e2, ev2} =
        grant(ctx, %{"parent_grant" => parent_id, "action" => "*"}, signer: ctx.bot)

      assert {:error, :not_covered} = Planner.plan(e2, ev2, facts)

      # grant nadrzędny nie jest delegable
      assert {:error, :parent_not_delegable} =
               Planner.plan(e, ev, %{facts | grants: [%{parent | delegable: false}]})

      # ważność grantu nadrzędnego zależy od czasu serwera, a nie od ts z koperty
      expiring = %{parent | expires_at: ~U[2026-10-06 11:00:00Z]}

      assert {:error, {:grant_inactive, ^parent_id}} =
               Planner.plan(e, ev, %{facts | grants: [expiring]})

      # dziecko bez własnego wygaśnięcia przeżyłoby rodzica, więc nie mieści się w jego oknie
      earlier = %{facts | grants: [expiring], now: ~U[2026-10-06 10:00:00Z]}
      assert {:error, :window_exceeds_parent} = Planner.plan(e, ev, earlier)

      # a dziecko wygasające przed rodzicem jest przyjmowane, dopóki rodzic obowiązuje
      {e3, ev3} =
        grant(
          ctx,
          %{
            "subject" => id(subject),
            "parent_grant" => parent_id,
            "expires_at" => DateTime.to_unix(~U[2026-10-06 10:30:00Z])
          },
          signer: ctx.bot
        )

      assert {:ok, _} = Planner.plan(e3, ev3, earlier)
    end

    test "klucz podmiotu musi być znany i być kluczem sygnowania", ctx do
      {e, ev} = grant(ctx)

      assert {:error, :unknown_subject_key} = Planner.plan(e, ev, %{ctx.facts | subject_key: nil})

      assert {:error, :subject_not_signing_key} =
               Planner.plan(e, ev, %{ctx.facts | subject_key: @active_auth})
    end

    test "łańcuch: nieznana tożsamość", ctx do
      {e, ev} = grant(ctx)
      assert {:error, :unknown_identity} = Planner.plan(e, ev, %{ctx.facts | identity: nil})
      assert {:error, :unknown_identity} = Planner.plan(e, ev, %{ctx.facts | head: nil})
    end

    test "łańcuch: zły seq i zły poprzednik", ctx do
      {e, ev} = grant(ctx, %{}, seq: 2)
      assert {:error, {:bad_seq, 1}} = Planner.plan(e, ev, ctx.facts)

      {e, ev} = grant(ctx, %{}, seq: 1)
      facts = %{ctx.facts | head: %{seq: 3, id: "x"}}
      assert {:error, {:bad_seq, 4}} = Planner.plan(e, ev, facts)

      {e, ev} = grant(ctx, %{}, prev: "inny")
      assert {:error, :bad_prev} = Planner.plan(e, ev, ctx.facts)
    end

    test "łańcuch jest sprawdzany przed uprawnieniami", ctx do
      {e, ev} = grant(ctx, %{}, seq: 5, signer: ctx.bot)
      assert {:error, {:bad_seq, 1}} = Planner.plan(e, ev, ctx.facts)
    end

    test "podpisujący: nieznany, nie sygnowania, unieważniony, nieuprawniony", ctx do
      {e, ev} = grant(ctx)

      assert {:error, :unknown_signer} = Planner.plan(e, ev, %{ctx.facts | signer_key: nil})

      assert {:error, :not_signing_key} =
               Planner.plan(e, ev, %{ctx.facts | signer_key: @active_auth})

      assert {:error, :key_revoked} =
               Planner.plan(e, ev, %{ctx.facts | signer_key: %{kind: :signing, status: :revoked}})

      {e, ev} = grant(ctx, %{}, signer: ctx.bot)
      assert {:error, :not_authorized} = Planner.plan(e, ev, ctx.facts)
    end

    test "nieobsługiwany typ zdarzenia", ctx do
      {e, ev} = grant(ctx, %{}, type: "key.revoke")
      assert {:error, {:unsupported_type, "key.revoke"}} = Planner.plan(e, ev, ctx.facts)
    end

    test "powtórzone zdarzenie ma pierwszeństwo", ctx do
      {e, ev} = grant(ctx)
      assert {:error, :duplicate_event} = Planner.plan(e, ev, %{ctx.facts | event_exists?: true})
    end
  end

  # profile.update

  describe "profile.update" do
    @now ~U[2026-10-06 12:00:00Z]

    setup do
      founder = kp()
      editor = kp()

      {_g, genesis} =
        founder
        |> then(&Envelope.genesis(%{"kind" => "user", "auth_keys" => [id(kp())]}, &1))
        |> verified()

      grant_id = Crypto.encode(:crypto.strong_rand_bytes(32))

      facts = %Facts{
        identity: %{id: genesis.id, profile: %{"display_name" => "Pelagia", "bio" => "stare"}},
        head: %{seq: 0, id: genesis.id},
        founding_key_id: id(founder),
        signer_key: @active_signing,
        now: @now
      }

      {:ok, founder: founder, editor: editor, genesis: genesis, facts: facts, grant_id: grant_id}
    end

    defp profile_grant(ctx, resource_suffix, opts \\ []) do
      %{
        id: ctx.grant_id,
        issuer_key_id: id(ctx.founder),
        subject_key_id: id(ctx.editor),
        parent_grant_id: nil,
        action: Keyword.get(opts, :action, "profile.update"),
        resource: ctx.genesis.id <> resource_suffix,
        not_before: nil,
        expires_at: Keyword.get(opts, :expires_at),
        revoked_at: Keyword.get(opts, :revoked_at),
        delegable: false
      }
    end

    defp profile_update(ctx, fields, opts \\ []) do
      %{
        type: "profile.update",
        seq: Keyword.get(opts, :seq, 1),
        identity: ctx.genesis.id,
        prev: ctx.genesis.id,
        body: Keyword.get(opts, :body, %{"fields" => fields})
      }
      |> Envelope.sign(Keyword.get(opts, :signer, ctx.founder))
      |> verified()
    end

    test "klucz założycielski zmienia profil bez grantów", ctx do
      {e, ev} = profile_update(ctx, %{"bio" => "nowe", "location" => "Warszawa"})

      assert {:ok, ops} = Planner.plan(e, ev, ctx.facts)
      assert kinds(ops) == [:event, :profile]

      assert [%{type: "profile.update", seq: 1, identity_id: identity}] = op(ops, :event)
      assert identity == ctx.genesis.id

      assert [%{identity_id: ^identity, profile: profile}] = op(ops, :profile)
      assert profile == %{"display_name" => "Pelagia", "bio" => "nowe", "location" => "Warszawa"}
    end

    test "null usuwa pole, a brak profilu w faktach jest traktowany jak pusty profil", ctx do
      {e, ev} = profile_update(ctx, %{"bio" => nil})
      assert {:ok, ops} = Planner.plan(e, ev, ctx.facts)
      assert [%{profile: %{"display_name" => "Pelagia"} = profile}] = op(ops, :profile)
      refute Map.has_key?(profile, "bio")

      facts = %{ctx.facts | identity: %{id: ctx.genesis.id}}
      {e, ev} = profile_update(ctx, %{"bio" => "x"})
      assert {:ok, ops} = Planner.plan(e, ev, facts)
      assert [%{profile: %{"bio" => "x"}}] = op(ops, :profile)
    end

    test "niepoprawne zmiany", ctx do
      for {fields, error} <- [
            {%{}, "fields"},
            {"bio", "fields"},
            {%{"admin" => "x"}, "fields.admin"},
            {%{"bio" => ""}, "fields.bio"},
            {%{"website" => "ftp://x"}, "fields.website"}
          ] do
        {e, ev} = profile_update(ctx, fields)
        assert {:error, {:invalid_body, ^error}} = Planner.plan(e, ev, ctx.facts), inspect(fields)
      end

      {e, ev} = profile_update(ctx, nil, body: %{})
      assert {:error, {:invalid_body, "fields"}} = Planner.plan(e, ev, ctx.facts)
    end

    test "delegat z grantem na jedno pole zmienia tylko to pole", ctx do
      facts = %{ctx.facts | grants: [profile_grant(ctx, "/profile/bio")]}

      {e, ev} = profile_update(ctx, %{"bio" => "z tłumaczenia"}, signer: ctx.editor)
      assert {:ok, ops} = Planner.plan(e, ev, facts)

      assert [%{profile: %{"bio" => "z tłumaczenia", "display_name" => "Pelagia"}}] =
               op(ops, :profile)

      {e, ev} = profile_update(ctx, %{"display_name" => "Kto inny"}, signer: ctx.editor)
      assert {:error, {:not_authorized, "display_name"}} = Planner.plan(e, ev, facts)

      # jedno niedozwolone pole odrzuca całe zdarzenie, nawet z dozwolonym obok
      {e, ev} = profile_update(ctx, %{"bio" => "x", "location" => "y"}, signer: ctx.editor)
      assert {:error, {:not_authorized, "location"}} = Planner.plan(e, ev, facts)
    end

    test "grant na cały profil, szeroki wzorzec akcji i grant z innej przestrzeni", ctx do
      {e, ev} =
        profile_update(ctx, %{"bio" => "x", "website" => "https://a.pl"}, signer: ctx.editor)

      assert {:ok, _} =
               Planner.plan(e, ev, %{ctx.facts | grants: [profile_grant(ctx, "/profile/*")]})

      assert {:ok, _} =
               Planner.plan(e, ev, %{
                 ctx.facts
                 | grants: [profile_grant(ctx, "/*", action: "profile.*")]
               })

      assert {:ok, _} =
               Planner.plan(e, ev, %{ctx.facts | grants: [profile_grant(ctx, "/*", action: "*")]})

      # inna akcja albo inny zasób niż profil nie wystarczają
      assert {:error, {:not_authorized, "bio"}} =
               Planner.plan(e, ev, %{
                 ctx.facts
                 | grants: [profile_grant(ctx, "/profile/*", action: "project.edit")]
               })

      assert {:error, {:not_authorized, "bio"}} =
               Planner.plan(e, ev, %{ctx.facts | grants: [profile_grant(ctx, "/lang/*")]})

      assert {:error, {:not_authorized, "bio"}} = Planner.plan(e, ev, ctx.facts)
    end

    test "grant wygasły albo unieważniony nie upoważnia; liczy się czas serwera", ctx do
      {e, ev} = profile_update(ctx, %{"bio" => "x"}, signer: ctx.editor)

      expired = profile_grant(ctx, "/profile/*", expires_at: ~U[2026-10-06 11:00:00Z])

      assert {:error, {:not_authorized, "bio"}} =
               Planner.plan(e, ev, %{ctx.facts | grants: [expired]})

      # ten sam grant jeszcze obowiązuje, gdy serwerowy zegar stoi przed wygaśnięciem
      assert {:ok, _} =
               Planner.plan(e, ev, %{ctx.facts | grants: [expired], now: ~U[2026-10-06 10:00:00Z]})

      revoked = profile_grant(ctx, "/profile/*", revoked_at: ~U[2026-10-06 11:00:00Z])

      assert {:error, {:not_authorized, "bio"}} =
               Planner.plan(e, ev, %{ctx.facts | grants: [revoked]})
    end

    test "grant bez ważnego łańcucha do klucza założycielskiego nie upoważnia", ctx do
      forged = %{profile_grant(ctx, "/profile/*") | issuer_key_id: "ktos-inny"}
      {e, ev} = profile_update(ctx, %{"bio" => "x"}, signer: ctx.editor)

      assert {:error, {:not_authorized, "bio"}} =
               Planner.plan(e, ev, %{ctx.facts | grants: [forged]})
    end

    test "łańcuch i podpisujący są sprawdzani przed uprawnieniami", ctx do
      {e, ev} = profile_update(ctx, %{"bio" => "x"}, seq: 4, signer: ctx.editor)
      assert {:error, {:bad_seq, 1}} = Planner.plan(e, ev, ctx.facts)

      {e, ev} = profile_update(ctx, %{"bio" => "x"})
      assert {:error, :unknown_signer} = Planner.plan(e, ev, %{ctx.facts | signer_key: nil})

      assert {:error, :key_revoked} =
               Planner.plan(e, ev, %{ctx.facts | signer_key: %{kind: :signing, status: :revoked}})

      assert {:error, :unknown_identity} = Planner.plan(e, ev, %{ctx.facts | identity: nil})
    end

    test "powtórzone zdarzenie", ctx do
      {e, ev} = profile_update(ctx, %{"bio" => "x"})
      assert {:error, :duplicate_event} = Planner.plan(e, ev, %{ctx.facts | event_exists?: true})
    end

    test "profile.update jest na liście obsługiwanych typów" do
      assert "profile.update" in Planner.supported_types()
    end
  end
end
