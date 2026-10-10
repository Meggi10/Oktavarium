defmodule Oktavarium.LogTest do
  use Oktavarium.DataCase

  alias Oktavarium.{Cli, Crypto, Envelope, Log}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.{IdentityAuthKey, Key}
  alias Oktavarium.Log.Event

  defp kp, do: Crypto.generate_keypair()
  defp id(keypair), do: Crypto.key_id(keypair.public)

  defp found(founder, auth, body \\ %{}) do
    body = Map.merge(%{"kind" => "user", "auth_keys" => [id(auth)]}, body)
    envelope = Envelope.genesis(body, founder)
    {envelope, Log.append(envelope)}
  end

  defp found!(founder, auth, body \\ %{}) do
    {_envelope, {:ok, event}} = found(founder, auth, body)
    event
  end

  defp grant_envelope(signer, identity, seq, prev, subject, changes \\ %{}) do
    body =
      Map.merge(
        %{"subject" => id(subject), "action" => "project.edit", "resource" => identity <> "/*"},
        changes
      )

    Envelope.sign(
      %{type: "grant.create", seq: seq, identity: identity, prev: prev, body: body},
      signer
    )
  end

  defp counts do
    %{
      identities: Repo.aggregate(Identity, :count),
      keys: Repo.aggregate(Key, :count),
      links: Repo.aggregate(IdentityAuthKey, :count),
      events: Repo.aggregate(Event, :count),
      grants: Repo.aggregate(Grant, :count)
    }
  end

  describe "genesis" do
    test "zapisuje tożsamość, klucze, powiązanie i zdarzenie z surowymi bajtami" do
      founder = kp()
      auth = kp()
      {envelope, {:ok, event}} = found(founder, auth, %{"handle" => "pelagia"})

      identity = Repo.get!(Identity, event.id)
      assert identity.kind == :user
      assert identity.handle == "pelagia"
      assert identity.parent_id == nil

      signing = Repo.get!(Key, id(founder))
      assert signing.kind == :signing
      assert signing.home_identity_id == event.id
      assert signing.public_key == founder.public

      auth_key = Repo.get!(Key, id(auth))
      assert auth_key.kind == :auth
      assert auth_key.home_identity_id == nil

      link = Repo.get_by!(IdentityAuthKey, identity_id: event.id, key_id: id(auth))
      assert link.status == :active
      assert link.added_event_id == event.id

      stored = Repo.get!(Event, event.id)
      assert stored.identity_id == event.id
      assert stored.seq == 0
      assert stored.prev == nil
      assert stored.type == "identity.genesis"
      assert stored.signer_key_id == id(founder)
      assert stored.payload == envelope.payload
      assert stored.signature == envelope.signature

      # zapisane bajty nadal przechodzą weryfikację podpisu
      restored = %Envelope{
        payload: stored.payload,
        signature: stored.signature,
        signer: founder.public
      }

      assert {:ok, %{id: id}} = Envelope.verify(restored)
      assert id == event.id
    end

    test "powtórzenie tej samej koperty jest odrzucane i nic nie zmienia" do
      founder = kp()
      auth = kp()
      {envelope, {:ok, _}} = found(founder, auth)
      before = counts()

      assert {:error, :duplicate_event} = Log.append(envelope)
      assert counts() == before
    end

    test "bez klucza autoryzacji nic nie jest zapisywane" do
      envelope = Envelope.genesis(%{"kind" => "user"}, kp())

      assert {:error, :auth_key_required} = Log.append(envelope)
      assert counts() == %{identities: 0, keys: 0, links: 0, events: 0, grants: 0}
    end

    test "zajęty handle" do
      found!(kp(), kp(), %{"handle" => "pelagia"})
      before = counts()

      second = kp()
      {_envelope, result} = found(second, kp(), %{"handle" => "pelagia"})

      assert result == {:error, :handle_taken}
      assert counts() == before
      assert Repo.get(Key, id(second)) == nil
    end

    test "klucz sygnowania może założyć tylko jedną tożsamość" do
      founder = kp()
      found!(founder, kp())

      {_envelope, result} = found(founder, kp(), %{"kind" => "org"})
      assert result == {:error, :signing_key_already_registered}
    end

    test "ten sam klucz autoryzacji obsługuje wiele tożsamości" do
      auth = kp()
      first = found!(kp(), auth)
      second = found!(kp(), auth)

      assert Repo.aggregate(from(k in Key, where: k.id == ^id(auth)), :count) == 1

      linked =
        from(l in IdentityAuthKey, where: l.key_id == ^id(auth), select: l.identity_id)
        |> Repo.all()
        |> Enum.sort()

      assert linked == Enum.sort([first.id, second.id])
    end

    test "klucz sygnowania nie może zostać kluczem autoryzacji innej tożsamości" do
      founder = kp()
      found!(founder, kp())

      {_envelope, result} = found(kp(), founder)
      assert result == {:error, {:key_kind_conflict, id(founder)}}
    end

    test "uszkodzona koperta" do
      envelope = Envelope.genesis(%{"kind" => "user", "auth_keys" => [id(kp())]}, kp())
      tampered = %{envelope | payload: String.replace(envelope.payload, "user", "admn")}

      assert {:error, {:invalid_envelope, :bad_signature}} = Log.append(tampered)
      assert counts().events == 0
    end
  end

  describe "grant.create" do
    setup do
      founder = kp()
      auth = kp()
      bot = kp()
      pelagia = found!(founder, auth, %{"handle" => "pelagia"})
      # klucz podmiotu musi być znany, więc bot zakłada własną (ograniczoną) tożsamość
      bot_identity = found!(bot, auth, %{"handle" => "pelagia-bot"})
      {:ok, founder: founder, auth: auth, bot: bot, pelagia: pelagia, bot_identity: bot_identity}
    end

    test "klucz założycielski nadaje uprawnienie, a następne zdarzenia się łańcuchują", ctx do
      expires = DateTime.to_unix(~U[2099-01-01 00:00:00Z])

      envelope =
        grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot, %{
          "expires_at" => expires
        })

      assert {:ok, event} = Log.append(envelope)
      assert event.seq == 1

      grant = Repo.get!(Grant, event.id)
      assert grant.identity_id == ctx.pelagia.id
      assert grant.issuer_key_id == id(ctx.founder)
      assert grant.subject_key_id == id(ctx.bot)
      assert grant.action == "project.edit"
      assert grant.resource == ctx.pelagia.id <> "/*"
      assert grant.not_before == nil
      assert DateTime.compare(grant.expires_at, ~U[2099-01-01 00:00:00Z]) == :eq
      assert grant.parent_grant_id == nil

      stored = Repo.get!(Event, event.id)
      assert stored.prev == ctx.pelagia.id
      assert stored.payload == envelope.payload

      second =
        grant_envelope(ctx.founder, ctx.pelagia.id, 2, event.id, ctx.bot, %{
          "action" => "project.*"
        })

      assert {:ok, %{seq: 2}} = Log.append(second)

      assert Repo.aggregate(from(g in Grant, where: g.identity_id == ^ctx.pelagia.id), :count) ==
               2
    end

    test "powtórzenie koperty jest odrzucane", ctx do
      envelope = grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot)
      assert {:ok, _} = Log.append(envelope)
      before = counts()

      assert {:error, :duplicate_event} = Log.append(envelope)
      assert counts() == before
    end

    test "zły seq i zły poprzednik", ctx do
      {:ok, first} =
        Log.append(grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot))

      before = counts()

      # rozwidlenie: inne zdarzenie z tym samym seq
      fork =
        grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot, %{
          "action" => "x.y"
        })

      assert {:error, {:bad_seq, 2}} = Log.append(fork)

      # luka
      assert {:error, {:bad_seq, 2}} =
               Log.append(grant_envelope(ctx.founder, ctx.pelagia.id, 3, first.id, ctx.bot))

      # dobry seq, zły poprzednik
      assert {:error, :bad_prev} =
               Log.append(grant_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.pelagia.id, ctx.bot))

      assert counts() == before
    end

    test "cudzy klucz nie może nadawać uprawnień w przestrzeni tożsamości", ctx do
      before = counts()

      # bot jest znanym kluczem sygnowania, ale nie założycielskim kluczem Violi
      envelope = grant_envelope(ctx.bot, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot)

      assert {:error, :not_authorized} = Log.append(envelope)
      assert counts() == before
    end

    test "nieznany klucz podmiotu", ctx do
      stranger = kp()
      envelope = grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, stranger)

      assert {:error, :unknown_subject_key} = Log.append(envelope)
    end

    test "podmiotem nie może być klucz autoryzacji", ctx do
      envelope = grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.auth)
      assert {:error, :subject_not_signing_key} = Log.append(envelope)
    end

    test "nieznana tożsamość", ctx do
      ghost = Crypto.encode(:crypto.strong_rand_bytes(32))
      envelope = grant_envelope(ctx.founder, ghost, 1, ghost, ctx.bot)

      assert {:error, :unknown_identity} = Log.append(envelope)
    end

    test "klucz założycielski nie wskazuje grantu nadrzędnego", ctx do
      envelope =
        grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot, %{
          "parent_grant" => ctx.pelagia.id
        })

      assert {:error, :unexpected_parent_grant} = Log.append(envelope)
    end

    test "uszkodzony grant", ctx do
      envelope = grant_envelope(ctx.founder, ctx.pelagia.id, 1, ctx.pelagia.id, ctx.bot)

      tampered = %{
        envelope
        | signature: Crypto.sign(:login, envelope.payload, ctx.founder.private)
      }

      assert {:error, {:invalid_envelope, :bad_signature}} = Log.append(tampered)
    end
  end

  describe "delegowanie" do
    setup do
      founder = kp()
      auth = kp()
      bot = kp()
      carol = kp()
      pelagia = found!(founder, auth, %{"handle" => "pelagia"})
      found!(bot, auth, %{"handle" => "pelagia-bot"})
      found!(carol, auth, %{"handle" => "carol"})

      # bot dostaje prawo do zarządzania językami i może je przekazywać dalej
      {:ok, g1} =
        Log.append(
          grant_envelope(founder, pelagia.id, 1, pelagia.id, bot, %{
            "action" => "project.*",
            "resource" => pelagia.id <> "/lang/*",
            "delegable" => true
          })
        )

      {:ok, founder: founder, bot: bot, carol: carol, pelagia: pelagia, g1: g1}
    end

    # delegowanie przez bota na podstawie g1 jako kolejne zdarzenie dziennika Violi
    defp delegation(ctx, changes \\ %{}, opts \\ []) do
      body =
        Map.merge(
          %{
            "action" => "project.edit",
            "resource" => ctx.pelagia.id <> "/lang/pl",
            "parent_grant" => Keyword.get(opts, :parent, ctx.g1.id)
          },
          changes
        )

      grant_envelope(
        Keyword.get(opts, :signer, ctx.bot),
        ctx.pelagia.id,
        Keyword.get(opts, :seq, 2),
        Keyword.get(opts, :prev, ctx.g1.id),
        Keyword.get(opts, :subject, ctx.carol),
        body
      )
    end

    test "klucz z grantem delegable wystawia węższy grant", ctx do
      assert {:ok, event} = Log.append(delegation(ctx))

      grant = Repo.get!(Grant, event.id)
      assert grant.parent_grant_id == ctx.g1.id
      assert grant.issuer_key_id == id(ctx.bot)
      assert grant.subject_key_id == id(ctx.carol)
      assert grant.resource == ctx.pelagia.id <> "/lang/pl"
      assert grant.delegable == false

      assert :ok = Log.verify(ctx.pelagia.id)
    end

    test "grant nie może być szerszy niż nadrzędny", ctx do
      before = counts()

      assert {:error, :not_covered} = Log.append(delegation(ctx, %{"action" => "*"}))

      assert {:error, :not_covered} =
               Log.append(delegation(ctx, %{"resource" => ctx.pelagia.id <> "/*"}))

      assert {:error, :not_covered} =
               Log.append(delegation(ctx, %{"resource" => ctx.pelagia.id <> "/readme"}))

      assert counts() == before
    end

    test "okno czasowe musi mieścić się w oknie grantu nadrzędnego", ctx do
      {:ok, limited} =
        Log.append(
          grant_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, ctx.bot, %{
            "action" => "project.*",
            "resource" => ctx.pelagia.id <> "/lang/*",
            "delegable" => true,
            "expires_at" => DateTime.to_unix(~U[2099-01-01 00:00:00Z])
          })
        )

      opts = [parent: limited.id, seq: 3, prev: limited.id]

      assert {:error, :window_exceeds_parent} = Log.append(delegation(ctx, %{}, opts))

      later = %{"expires_at" => DateTime.to_unix(~U[2100-01-01 00:00:00Z])}
      assert {:error, :window_exceeds_parent} = Log.append(delegation(ctx, later, opts))

      sooner = %{"expires_at" => DateTime.to_unix(~U[2098-01-01 00:00:00Z])}
      assert {:ok, _} = Log.append(delegation(ctx, sooner, opts))
    end

    test "tylko podmiot grantu może go użyć jako nadrzędnego", ctx do
      assert {:error, :not_authorized} =
               Log.append(delegation(ctx, %{}, signer: ctx.carol, subject: ctx.bot))
    end

    test "grant bez delegable pozwala korzystać, ale nie przekazywać", ctx do
      {:ok, plain} =
        Log.append(
          grant_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, ctx.carol, %{
            "action" => "project.edit",
            "resource" => ctx.pelagia.id <> "/lang/pl"
          })
        )

      opts = [parent: plain.id, signer: ctx.carol, subject: ctx.bot, seq: 3, prev: plain.id]
      assert {:error, :parent_not_delegable} = Log.append(delegation(ctx, %{}, opts))
    end

    test "nieznany grant nadrzędny", ctx do
      unknown = Crypto.encode(:crypto.strong_rand_bytes(32))
      assert {:error, :unknown_parent_grant} = Log.append(delegation(ctx, %{}, parent: unknown))
    end

    test "unieważniony grant nadrzędny odcina delegowanie", ctx do
      from(g in Grant, where: g.id == ^ctx.g1.id)
      |> Repo.update_all(set: [revoked_at: ~U[2026-01-01 00:00:00Z]])

      assert {:error, {:grant_inactive, id}} = Log.append(delegation(ctx))
      assert id == ctx.g1.id
    end

    test "unieważnienie przodka odcina całą dalszą część łańcucha", ctx do
      # g1 (bot) -> g2 (carol, delegable) -> carol deleguje dalej na bota
      {:ok, g2} = Log.append(delegation(ctx, %{"delegable" => true}))

      from(g in Grant, where: g.id == ^ctx.g1.id)
      |> Repo.update_all(set: [revoked_at: ~U[2026-01-01 00:00:00Z]])

      further =
        delegation(ctx, %{"resource" => ctx.pelagia.id <> "/lang/de"},
          parent: g2.id,
          signer: ctx.carol,
          subject: ctx.bot,
          seq: 3,
          prev: g2.id
        )

      assert {:error, {:grant_inactive, id}} = Log.append(further)
      assert id == ctx.g1.id
    end

    test "wygasły grant nadrzędny", ctx do
      {:ok, expired} =
        Log.append(
          grant_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, ctx.bot, %{
            "action" => "project.*",
            "resource" => ctx.pelagia.id <> "/lang/*",
            "delegable" => true,
            "expires_at" => DateTime.to_unix(~U[2020-01-01 00:00:00Z])
          })
        )

      opts = [parent: expired.id, seq: 3, prev: expired.id]
      assert {:error, {:grant_inactive, id}} = Log.append(delegation(ctx, %{}, opts))
      assert id == expired.id
    end

    test "grant spoza tej tożsamości nie może być nadrzędnym", ctx do
      # grant z dziennika bota, w którym bot jest założycielem
      bot_identity = Repo.get_by!(Key, id: id(ctx.bot)).home_identity_id

      {:ok, foreign} =
        Log.append(
          grant_envelope(ctx.bot, bot_identity, 1, bot_identity, ctx.carol, %{
            "action" => "project.*",
            "resource" => bot_identity <> "/*",
            "delegable" => true
          })
        )

      assert {:error, :unknown_parent_grant} =
               Log.append(delegation(ctx, %{}, parent: foreign.id))
    end
  end

  describe "dziennik tożsamości jako źródło prawdy" do
    setup do
      founder = kp()
      bot = kp()
      pelagia = found!(founder, kp())
      found!(bot, kp())
      {:ok, g1} = Log.append(grant_envelope(founder, pelagia.id, 1, pelagia.id, bot))

      {:ok, g2} =
        Log.append(grant_envelope(founder, pelagia.id, 2, g1.id, bot, %{"action" => "x.y"}))

      {:ok, founder: founder, bot: bot, pelagia: pelagia, g1: g1, g2: g2}
    end

    test "envelopes/1 oddaje zapisane koperty w kolejności i bez zmian", ctx do
      envelopes = Log.envelopes(ctx.pelagia.id)

      assert length(envelopes) == 3
      assert Enum.map(envelopes, &Envelope.id/1) == [ctx.pelagia.id, ctx.g1.id, ctx.g2.id]
      assert Enum.all?(envelopes, &match?({:ok, _}, Envelope.verify(&1)))
    end

    test "dzienniki tożsamości są niezależne", ctx do
      assert length(Log.envelopes(ctx.pelagia.id)) == 3

      assert Repo.aggregate(from(e in Event, where: e.identity_id != ^ctx.pelagia.id), :count) ==
               1

      assert :ok = Log.verify(ctx.pelagia.id)
    end

    test "verify/1 akceptuje nienaruszony dziennik i odrzuca nieznaną tożsamość", ctx do
      assert :ok = Log.verify(ctx.pelagia.id)
      assert {:error, :unknown_identity} = Log.verify("nie-ma-takiej")
    end

    test "verify/1 wykrywa zmianę zapisanych bajtów", ctx do
      from(e in Event, where: e.id == ^ctx.g1.id) |> Repo.update_all(set: [payload: "inne bajty"])

      assert {:error, {:corrupt, 1, :bad_signature}} = Log.verify(ctx.pelagia.id)
    end

    test "verify/1 wykrywa usunięcie zdarzenia ze środka dziennika", ctx do
      from(e in Event, where: e.id == ^ctx.g1.id) |> Repo.delete_all()

      assert {:error, {:corrupt, 2, :bad_seq}} = Log.verify(ctx.pelagia.id)
    end

    test "verify/1 wykrywa podmianę numeru kolejnego w projekcji", ctx do
      from(e in Event, where: e.id == ^ctx.g2.id) |> Repo.update_all(set: [seq: 5])

      assert {:error, {:corrupt, 5, :bad_seq}} = Log.verify(ctx.pelagia.id)
    end
  end

  describe "profile.update" do
    setup do
      founder = kp()
      editor = kp()
      stranger = kp()
      auth = kp()
      pelagia = found!(founder, auth, %{"handle" => "pelagia"})
      found!(editor, auth, %{"handle" => "pelagia-editor"})
      other = found!(stranger, auth, %{"handle" => "obca"})

      # edytor może zmieniać tylko bio
      {:ok, g1} =
        Log.append(
          grant_envelope(founder, pelagia.id, 1, pelagia.id, editor, %{
            "action" => "profile.update",
            "resource" => pelagia.id <> "/profile/bio"
          })
        )

      {:ok,
       founder: founder,
       editor: editor,
       stranger: stranger,
       pelagia: pelagia,
       other: other,
       g1: g1}
    end

    defp profile_envelope(signer, identity, seq, prev, fields) do
      Envelope.sign(
        %{
          type: "profile.update",
          seq: seq,
          identity: identity,
          prev: prev,
          body: %{"fields" => fields}
        },
        signer
      )
    end

    defp profile_of(identity_id), do: Repo.get!(Identity, identity_id).profile

    test "klucz założycielski ustawia, scala i usuwa pola; dziennik pozostaje poprawny", ctx do
      assert profile_of(ctx.pelagia.id) == %{}

      {:ok, e2} =
        Log.append(
          profile_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, %{
            "display_name" => "Pelagia",
            "bio" => "stare"
          })
        )

      assert profile_of(ctx.pelagia.id) == %{"display_name" => "Pelagia", "bio" => "stare"}

      {:ok, e3} =
        Log.append(
          profile_envelope(ctx.founder, ctx.pelagia.id, 3, e2.id, %{
            "bio" => nil,
            "location" => "Warszawa"
          })
        )

      assert profile_of(ctx.pelagia.id) == %{
               "display_name" => "Pelagia",
               "location" => "Warszawa"
             }

      assert Repo.get!(Event, e3.id).type == "profile.update"
      assert :ok = Log.verify(ctx.pelagia.id)
    end

    test "delegat z grantem na jedno pole zmienia tylko to pole", ctx do
      {:ok, e2} =
        Log.append(
          profile_envelope(ctx.editor, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "od edytora"})
        )

      assert profile_of(ctx.pelagia.id) == %{"bio" => "od edytora"}

      before = counts()

      assert {:error, {:not_authorized, "display_name"}} =
               Log.append(
                 profile_envelope(ctx.editor, ctx.pelagia.id, 3, e2.id, %{
                   "display_name" => "Ktoś"
                 })
               )

      assert {:error, {:not_authorized, "location"}} =
               Log.append(
                 profile_envelope(ctx.editor, ctx.pelagia.id, 3, e2.id, %{
                   "bio" => "y",
                   "location" => "z"
                 })
               )

      # odrzucone zdarzenie nic nie zmienia, także w polu, do którego edytor miał prawo
      assert counts() == before
      assert profile_of(ctx.pelagia.id) == %{"bio" => "od edytora"}
      assert :ok = Log.verify(ctx.pelagia.id)
    end

    test "klucz bez grantu nie zmienia cudzego profilu", ctx do
      before = counts()

      assert {:error, {:not_authorized, "bio"}} =
               Log.append(
                 profile_envelope(ctx.stranger, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "włam"})
               )

      assert counts() == before
      assert profile_of(ctx.pelagia.id) == %{}
    end

    test "unieważniony grant odbiera prawo do zmiany", ctx do
      ctx.g1.id
      |> then(&Repo.get!(Grant, &1))
      |> Ecto.Changeset.change(revoked_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      assert {:error, {:not_authorized, "bio"}} =
               Log.append(
                 profile_envelope(ctx.editor, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "x"})
               )

      # klucz założycielski nadal może
      assert {:ok, _} =
               Log.append(
                 profile_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "x"})
               )
    end

    test "wygasły grant odbiera prawo do zmiany (czas serwera)", ctx do
      ctx.g1.id
      |> then(&Repo.get!(Grant, &1))
      |> Ecto.Changeset.change(expires_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      assert {:error, {:not_authorized, "bio"}} =
               Log.append(
                 profile_envelope(ctx.editor, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "x"})
               )
    end

    test "dzienniki są niezależne: profil jednej tożsamości nie rusza drugiej", ctx do
      {:ok, _} =
        Log.append(
          profile_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "Pelagia"})
        )

      {:ok, _} =
        Log.append(
          profile_envelope(ctx.stranger, ctx.other.id, 1, ctx.other.id, %{"bio" => "Obca"})
        )

      assert profile_of(ctx.pelagia.id) == %{"bio" => "Pelagia"}
      assert profile_of(ctx.other.id) == %{"bio" => "Obca"}
      assert :ok = Log.verify(ctx.pelagia.id)
      assert :ok = Log.verify(ctx.other.id)
    end

    test "zły seq i niepoprawne pola nie zmieniają profilu", ctx do
      assert {:error, {:bad_seq, 2}} =
               Log.append(
                 profile_envelope(ctx.founder, ctx.pelagia.id, 5, ctx.g1.id, %{"bio" => "x"})
               )

      assert {:error, {:invalid_body, "fields.admin"}} =
               Log.append(
                 profile_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, %{"admin" => "x"})
               )

      assert profile_of(ctx.pelagia.id) == %{}
    end

    test "koperta profilu przechodzi ponowną weryfikację z zapisanych bajtów", ctx do
      {:ok, _} =
        Log.append(profile_envelope(ctx.founder, ctx.pelagia.id, 2, ctx.g1.id, %{"bio" => "x"}))

      assert [_, _, %Envelope{} = last] = Log.envelopes(ctx.pelagia.id)

      assert {:ok, %{type: "profile.update", body: %{"fields" => %{"bio" => "x"}}}} =
               Envelope.verify(last)
    end
  end

  describe "pliki z CLI" do
    @describetag :tmp_dir

    defp load!(path) do
      {:ok, envelope} = path |> File.read!() |> Jason.decode!() |> Envelope.from_map()
      envelope
    end

    test "koperty podpisane przez CLI przechodzą przez serwer w całości", %{tmp_dir: dir} do
      path = &Path.join(dir, &1)
      {:ok, %{id: _}} = Cli.gen_key("signing", path.("pelagia.key"))
      {:ok, %{id: _}} = Cli.gen_key("signing", path.("bot.key"))
      {:ok, %{id: auth_id}} = Cli.gen_key("auth", path.("laptop.key"))
      {:ok, %{id: bot_id}} = Cli.show_key(path.("bot.key"))

      {:ok, %{envelope: pelagia_genesis, event: pelagia}} =
        Cli.create_identity(path.("pelagia.key"),
          kind: "user",
          handle: "pelagia",
          auth_keys: [auth_id]
        )

      {:ok, %{envelope: bot_genesis}} =
        Cli.create_identity(path.("bot.key"),
          kind: "user",
          handle: "pelagia-bot",
          auth_keys: [auth_id]
        )

      :ok = Cli.write_envelope(path.("pelagia-0.json"), pelagia_genesis)
      :ok = Cli.write_envelope(path.("bot-0.json"), bot_genesis)

      {:ok, %{envelope: grant}} =
        Cli.create_grant(path.("pelagia.key"),
          after: path.("pelagia-0.json"),
          to: bot_id,
          action: "repo.push",
          resource: pelagia.id <> "/files/*",
          expires_at: "2099-01-01"
        )

      :ok = Cli.write_envelope(path.("pelagia-1.json"), grant)

      for file <- ["pelagia-0.json", "bot-0.json", "pelagia-1.json"] do
        assert {:ok, _event} = Log.append(load!(path.(file))), file
      end

      assert %Grant{action: "repo.push", subject_key_id: ^bot_id} =
               Repo.get_by!(Grant, identity_id: pelagia.id)

      assert counts() == %{identities: 2, keys: 3, links: 2, events: 3, grants: 1}
    end

    test "delegowanie przez CLI: bot przekazuje węższe uprawnienie dalej", %{tmp_dir: dir} do
      path = &Path.join(dir, &1)
      {:ok, _} = Cli.gen_key("signing", path.("pelagia.key"))
      {:ok, _} = Cli.gen_key("signing", path.("bot.key"))
      {:ok, _} = Cli.gen_key("signing", path.("carol.key"))
      {:ok, %{id: auth_id}} = Cli.gen_key("auth", path.("laptop.key"))
      {:ok, %{id: bot_id}} = Cli.show_key(path.("bot.key"))
      {:ok, %{id: carol_id}} = Cli.show_key(path.("carol.key"))

      identities =
        for {name, kind, handle} <- [
              {"pelagia", "user", "pelagia"},
              {"bot", "user", "pelagia-bot"},
              {"carol", "user", "carol"}
            ] do
          {:ok, %{envelope: envelope, event: event}} =
            Cli.create_identity(path.("#{name}.key"),
              kind: kind,
              handle: handle,
              auth_keys: [auth_id]
            )

          :ok = Cli.write_envelope(path.("#{name}-0.json"), envelope)
          {name, event}
        end

      pelagia = identities |> List.keyfind("pelagia", 0) |> elem(1)

      # Pelagia nadaje botowi prawo do języków z możliwością przekazywania dalej
      {:ok, %{envelope: g1, event: g1_event}} =
        Cli.create_grant(path.("pelagia.key"),
          after: path.("pelagia-0.json"),
          to: bot_id,
          action: "project.*",
          resource: pelagia.id <> "/lang/*",
          delegable: true
        )

      :ok = Cli.write_envelope(path.("pelagia-1.json"), g1)

      # bot dopisuje do dziennika Violi, więc zaczyna od pliku jej ostatniego zdarzenia
      {:ok, %{envelope: g2}} =
        Cli.create_grant(path.("bot.key"),
          after: path.("pelagia-1.json"),
          to: carol_id,
          action: "project.edit",
          resource: pelagia.id <> "/lang/pl",
          parent_grant: g1_event.id
        )

      :ok = Cli.write_envelope(path.("pelagia-2.json"), g2)

      for file <- [
            "pelagia-0.json",
            "bot-0.json",
            "carol-0.json",
            "pelagia-1.json",
            "pelagia-2.json"
          ] do
        assert {:ok, _event} = Log.append(load!(path.(file))), file
      end

      assert %Grant{issuer_key_id: ^bot_id, subject_key_id: ^carol_id, parent_grant_id: parent} =
               Repo.get_by!(Grant, subject_key_id: carol_id)

      assert parent == g1_event.id
      assert :ok = Log.verify(pelagia.id)

      assert {:ok, [_, _, _]} =
               Cli.verify_files([
                 path.("pelagia-0.json"),
                 path.("pelagia-1.json"),
                 path.("pelagia-2.json")
               ])
    end

    test "zmiana profilu przez CLI: założyciel i delegat z grantem na jedno pole", %{tmp_dir: dir} do
      path = &Path.join(dir, &1)
      {:ok, _} = Cli.gen_key("signing", path.("pelagia.key"))
      {:ok, _} = Cli.gen_key("signing", path.("bot.key"))
      {:ok, %{id: auth_id}} = Cli.gen_key("auth", path.("laptop.key"))
      {:ok, %{id: bot_id}} = Cli.show_key(path.("bot.key"))

      {:ok, %{envelope: g0, event: pelagia}} =
        Cli.create_identity(path.("pelagia.key"),
          kind: "user",
          handle: "pelagia",
          auth_keys: [auth_id]
        )

      {:ok, %{envelope: b0}} =
        Cli.create_identity(path.("bot.key"),
          kind: "user",
          handle: "pelagia-bot",
          auth_keys: [auth_id]
        )

      :ok = Cli.write_envelope(path.("pelagia-0.json"), g0)
      :ok = Cli.write_envelope(path.("bot-0.json"), b0)

      {:ok, %{envelope: p1}} =
        Cli.update_profile(path.("pelagia.key"),
          after: path.("pelagia-0.json"),
          set: ["display_name=Pelagia", "bio=a=b"]
        )

      :ok = Cli.write_envelope(path.("pelagia-1.json"), p1)

      {:ok, %{envelope: g2}} =
        Cli.create_grant(path.("pelagia.key"),
          after: path.("pelagia-1.json"),
          to: bot_id,
          action: "profile.update",
          resource: pelagia.id <> "/profile/bio"
        )

      :ok = Cli.write_envelope(path.("pelagia-2.json"), g2)

      {:ok, %{envelope: p3}} =
        Cli.update_profile(path.("bot.key"), after: path.("pelagia-2.json"), set: ["bio=od bota"])

      :ok = Cli.write_envelope(path.("pelagia-3.json"), p3)

      {:ok, %{envelope: p4}} =
        Cli.update_profile(path.("bot.key"),
          after: path.("pelagia-3.json"),
          set: ["display_name=Bot"]
        )

      :ok = Cli.write_envelope(path.("pelagia-4.json"), p4)

      for file <- [
            "pelagia-0.json",
            "bot-0.json",
            "pelagia-1.json",
            "pelagia-2.json",
            "pelagia-3.json"
          ] do
        assert {:ok, _event} = Log.append(load!(path.(file))), file
      end

      assert Repo.get!(Identity, pelagia.id).profile == %{
               "display_name" => "Pelagia",
               "bio" => "od bota"
             }

      # bot nie ma prawa do display_name; serwer odrzuca, choć CLI podpisało
      assert {:error, {:not_authorized, "display_name"}} =
               Log.append(load!(path.("pelagia-4.json")))

      assert Repo.get!(Identity, pelagia.id).profile == %{
               "display_name" => "Pelagia",
               "bio" => "od bota"
             }

      assert :ok = Log.verify(pelagia.id)
    end
  end
end
