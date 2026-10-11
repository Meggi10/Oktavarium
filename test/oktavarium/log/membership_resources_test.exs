defmodule Oktavarium.Log.MembershipResourcesTest do
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Envelope, Log, Replay}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Keys.IdentitySigningKey
  alias Oktavarium.Resources.Resource

  @hash String.duplicate("a", 64)

  defp try_event(state, type, body, signer \\ nil) do
    envelope =
      Envelope.sign(
        %{type: type, seq: state.seq + 1, identity: state.id, prev: state.head, body: body},
        signer || state.founder
      )

    Log.append(envelope)
  end

  # Klucz musi być znany platformie, zanim dostanie grant: dopisujemy go jako członka.
  defp member!(state, keypair), do: next!(state, "key.add", %{"key" => key_id(keypair)})

  defp put_body(path, extra \\ %{}) do
    Map.merge(
      %{"path" => path, "hash" => @hash, "size" => 10, "media_type" => "image/png"},
      extra
    )
  end

  describe "grant.revoke" do
    test "wystawca i założyciel cofają grant, drugie cofnięcie jest odrzucone" do
      state = found!()
      device = keypair()
      state = member!(state, device)
      {state, g} = grant!(state, device, "profile.update", "/profile/*")

      {state, _} = next_event!(state, "grant.revoke", %{"grant" => g.id})
      assert %Grant{revoked_at: %DateTime{}} = Repo.get!(Grant, g.id)
      assert {:error, :already_revoked} = try_event(state, "grant.revoke", %{"grant" => g.id})
    end

    test "nieznany grant i obcy podpisujący" do
      state = found!()
      device = keypair()
      stranger = keypair()
      state = state |> member!(device) |> member!(stranger)
      {state, g} = grant!(state, device, "profile.update", "/profile/*")

      assert {:error, :unknown_grant} =
               try_event(state, "grant.revoke", %{"grant" => String.duplicate("A", 43)})

      assert {:error, _} = try_event(state, "grant.revoke", %{"grant" => g.id}, stranger)

      assert {:error, {:invalid_body, "grant"}} =
               try_event(state, "grant.revoke", %{"grant" => 5})
    end

    test "cofnięty grant nie daje już uprawnień" do
      state = found!()
      device = keypair()
      state = member!(state, device)
      {state, g} = grant!(state, device, "profile.update", "/profile/bio")
      body = %{"fields" => %{"bio" => "x"}}

      state = next!(state, "profile.update", body, device)
      state = next!(state, "grant.revoke", %{"grant" => g.id})
      assert {:error, {:not_authorized, "bio"}} = try_event(state, "profile.update", body, device)
    end
  end

  describe "key.add / key.revoke" do
    test "dopisuje klucz urządzenia i cofa go razem z jego grantami" do
      state = found!()
      device = keypair()
      dev_id = key_id(device)

      state = next!(state, "key.add", %{"key" => dev_id, "label" => "laptop"})

      assert %IdentitySigningKey{status: :active, label: "laptop"} =
               Repo.get_by!(IdentitySigningKey, key_id: dev_id)

      {state, g} = grant!(state, device, "profile.update", "/profile/*")
      assert {:error, :already_member} = try_event(state, "key.add", %{"key" => dev_id})

      state = next!(state, "key.revoke", %{"key" => dev_id})

      assert %IdentitySigningKey{status: :revoked} =
               Repo.get_by!(IdentitySigningKey, key_id: dev_id)

      assert %Grant{revoked_at: %DateTime{}} = Repo.get!(Grant, g.id)
      assert {:error, :not_a_member} = try_event(state, "key.revoke", %{"key" => dev_id})

      # ponowne dopisanie po cofnięciu
      next!(state, "key.add", %{"key" => dev_id})

      assert %IdentitySigningKey{status: :active} =
               Repo.get_by!(IdentitySigningKey, key_id: dev_id)
    end

    test "klucz założycielski i klucz logowania nie mogą być członkiem" do
      state = found!()

      assert {:error, :already_member} =
               try_event(state, "key.add", %{"key" => key_id(state.founder)})

      assert {:error, {:key_kind_conflict, _}} =
               try_event(state, "key.add", %{"key" => key_id(state.auth)})

      assert {:error, :cannot_revoke_founding_key} =
               try_event(state, "key.revoke", %{"key" => key_id(state.founder)})

      assert {:error, {:invalid_body, "key"}} = try_event(state, "key.add", %{"key" => "nope"})

      assert {:error, {:invalid_body, "label"}} =
               try_event(state, "key.add", %{"key" => key_id(keypair()), "label" => ""})
    end

    test "delegat z grantem key.add może dopisać klucz, bez grantu nie" do
      state = found!()
      helper = keypair()
      other = key_id(keypair())

      state = member!(state, helper)
      assert {:error, :not_authorized} = try_event(state, "key.add", %{"key" => other}, helper)
      {state, _} = grant!(state, helper, "key.add", "/keys/*")
      assert {:ok, _} = try_event(state, "key.add", %{"key" => other}, helper)
    end

    test "ten sam klucz może być członkiem wielu tożsamości" do
      device = keypair()
      a = found!()
      b = found!()
      next!(a, "key.add", %{"key" => key_id(device)})
      next!(b, "key.add", %{"key" => key_id(device)})

      assert Repo.aggregate(
               from(m in IdentitySigningKey, where: m.key_id == ^key_id(device)),
               :count
             ) == 2
    end
  end

  describe "auth_key.add / auth_key.revoke" do
    alias Oktavarium.Keys.{IdentityAuthKey, Key}

    test "dopisuje drugie urządzenie logowania, cofa je i włącza ponownie" do
      state = found!()
      phone = keypair()
      phone_id = key_id(phone)

      state = next!(state, "auth_key.add", %{"key" => phone_id})
      assert %Key{kind: :auth, home_identity_id: nil} = Repo.get!(Key, phone_id)

      assert %IdentityAuthKey{status: :active} =
               Repo.get_by!(IdentityAuthKey, identity_id: state.id, key_id: phone_id)

      assert {:error, :already_member} = try_event(state, "auth_key.add", %{"key" => phone_id})

      state = next!(state, "auth_key.revoke", %{"key" => phone_id})

      assert %IdentityAuthKey{status: :revoked} =
               Repo.get_by!(IdentityAuthKey, identity_id: state.id, key_id: phone_id)

      assert {:error, :not_a_member} = try_event(state, "auth_key.revoke", %{"key" => phone_id})

      next!(state, "auth_key.add", %{"key" => phone_id})

      assert %IdentityAuthKey{status: :active} =
               Repo.get_by!(IdentityAuthKey, identity_id: state.id, key_id: phone_id)
    end

    test "nie można cofnąć ostatniego klucza logowania" do
      state = found!()

      assert {:error, :last_auth_key} =
               try_event(state, "auth_key.revoke", %{"key" => key_id(state.auth)})
    end

    test "klucz sygnowania nie może być kluczem logowania i odwrotnie" do
      state = found!()

      assert {:error, {:key_kind_conflict, _}} =
               try_event(state, "auth_key.add", %{"key" => key_id(state.founder)})

      assert {:error, {:key_kind_conflict, _}} =
               try_event(state, "key.add", %{"key" => key_id(state.auth)})
    end

    test "jeden klucz logowania może należeć do wielu tożsamości" do
      shared = keypair()
      a = found!(auth: shared)
      b = found!(auth: shared)
      assert a.id != b.id

      assert Repo.aggregate(
               from(l in IdentityAuthKey, where: l.key_id == ^key_id(shared)),
               :count
             ) == 2
    end

    test "wymaga uprawnienia auth_key.add, a granty ograniczają zakres" do
      state = found!()
      helper = keypair()
      state = member!(state, helper)
      other = key_id(keypair())

      assert {:error, :not_authorized} =
               try_event(state, "auth_key.add", %{"key" => other}, helper)

      {state, _} = grant!(state, helper, "auth_key.add", "/auth-keys/*")
      assert {:ok, _} = try_event(state, "auth_key.add", %{"key" => other}, helper)
    end
  end

  describe "resource.put / resource.delete" do
    test "zapis, nadpisanie i usunięcie zasobu" do
      state = found!()

      state =
        next!(state, "resource.put", put_body("images/kot.png", %{"meta" => %{"alt" => "kot"}}))

      assert %Resource{kind: :image, hash: @hash, meta: %{"alt" => "kot"}} =
               Repo.get_by!(Resource, path: "images/kot.png")

      other = String.duplicate("b", 64)
      state = next!(state, "resource.put", put_body("images/kot.png", %{"hash" => other}))
      assert %Resource{hash: ^other} = Repo.get_by!(Resource, path: "images/kot.png")
      assert Repo.aggregate(Resource, :count) == 1

      state = next!(state, "resource.delete", %{"path" => "images/kot.png"})
      assert Repo.aggregate(Resource, :count) == 0

      assert {:error, :unknown_resource} =
               try_event(state, "resource.delete", %{"path" => "images/kot.png"})
    end

    test "walidacja ścieżki, typu i skrótu" do
      state = found!()

      assert {:error, {:invalid_body, _}} =
               try_event(state, "resource.put", put_body("../etc/passwd"))

      assert {:error, {:invalid_body, _}} =
               try_event(state, "resource.put", put_body("images/A.png"))

      assert {:error, {:invalid_body, _}} =
               try_event(state, "resource.put", put_body("images/a.png", %{"hash" => "xyz"}))

      assert {:error, {:invalid_body, _}} =
               try_event(
                 state,
                 "resource.put",
                 put_body("audio/a.mp3", %{"media_type" => "image/png"})
               )
    end

    test "delegat może pisać tylko w zakresie swojego grantu" do
      state = found!()
      helper = keypair()
      state = member!(state, helper)
      {state, _} = grant!(state, helper, "resource.put", "/images/*")

      state = next!(state, "resource.put", put_body("images/ok.png"), helper)

      assert {:error, :not_authorized} =
               try_event(
                 state,
                 "resource.put",
                 put_body("audio/x.mp3", %{"media_type" => "audio/mpeg"}),
                 helper
               )
    end
  end

  test "Replay odtwarza członków i zasoby zgodnie z projekcją" do
    state = found!()
    device = keypair()
    state = member!(state, device)
    {state, g} = grant!(state, device, "resource.put", "/images/*")
    state = next!(state, "resource.put", put_body("images/a.png"))
    state = next!(state, "resource.put", put_body("images/b.png"), device)
    state = next!(state, "grant.revoke", %{"grant" => g.id})
    state = next!(state, "auth_key.add", %{"key" => key_id(keypair())})
    _ = next!(state, "key.revoke", %{"key" => key_id(device)})

    assert {:ok, report} = Replay.run()

    assert Enum.all?(report.drift, fn {_table, d} ->
             d.missing == [] and d.extra == [] and d.changed == []
           end)
  end
end
