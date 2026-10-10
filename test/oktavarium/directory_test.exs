defmodule Oktavarium.DirectoryTest do
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.Directory
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Log.Event

  defp identity!(id), do: Repo.get!(Identity, id)

  describe "list_identities/0" do
    test "pusta baza" do
      assert Directory.list_identities() == []
    end

    test "tożsamości z liczbą zdarzeń i głową dziennika" do
      a = found!(handle: "alfa")
      b = found!(handle: "beta")
      a = next!(a, "profile.update", %{"fields" => %{"bio" => "x"}})
      a = next!(a, "profile.update", %{"fields" => %{"bio" => "y"}})

      entries = Directory.list_identities()
      assert length(entries) == 2

      alfa = Enum.find(entries, &(&1.identity.id == a.id))
      assert alfa.events == 3
      assert alfa.head == a.head

      beta = Enum.find(entries, &(&1.identity.id == b.id))
      assert beta.events == 1
      assert beta.head == b.head
    end

    test "tożsamość restricted jest niewidoczna" do
      a = found!(handle: "alfa")
      identity!(a.id) |> Ecto.Changeset.change(visibility: :restricted) |> Repo.update!()

      assert Directory.list_identities() == []
      assert Directory.get_identity(a.id) == nil
      assert Directory.get_identity("alfa") == nil
    end
  end

  describe "get_identity/1" do
    test "po uchwycie i po id" do
      a = found!(handle: "alfa")
      assert %Identity{id: id} = Directory.get_identity("alfa")
      assert id == a.id
      assert %Identity{handle: "alfa"} = Directory.get_identity(a.id)
      assert Directory.get_identity("nie-ma") == nil
    end
  end

  describe "klucze" do
    test "klucz założycielski, klucze autoryzacji i liczba zdarzeń" do
      a = found!(handle: "alfa")
      a = next!(a, "profile.update", %{"fields" => %{"bio" => "x"}})
      identity = identity!(a.id)

      assert Directory.founding_key_id(identity) == key_id(a.founder)
      assert [%{key_id: auth_id, status: :active}] = Directory.auth_keys(identity)
      assert auth_id == key_id(a.auth)
      assert Directory.event_count(identity) == 2
    end

    test "key_homes/1 zna tylko klucze sygnowania z publiczną tożsamością domową" do
      a = found!(handle: "alfa")
      b = found!()

      homes =
        Directory.key_homes([key_id(a.founder), key_id(b.founder), key_id(a.auth), "nieznany"])

      assert homes[key_id(a.founder)] == %{identity_id: a.id, handle: "alfa"}
      assert homes[key_id(b.founder)] == %{identity_id: b.id, handle: nil}
      refute Map.has_key?(homes, key_id(a.auth))
      refute Map.has_key?(homes, "nieznany")
      assert Directory.key_homes([]) == %{}
    end
  end

  describe "grants/2" do
    setup do
      a = found!(handle: "alfa")
      {:ok, a: a, bot: found!()}
    end

    defp status_of(a, grant_id, now \\ DateTime.utc_now()) do
      a.id
      |> identity!()
      |> Directory.grants(now)
      |> Enum.find(&(&1.id == grant_id))
      |> Map.fetch!(:status)
    end

    test "aktywny, unieważniony, wygasły i jeszcze nieaktywny", %{a: a, bot: bot} do
      {a, active} = grant!(a, bot.founder, "profile.update", "/profile/bio")
      {a, revoked} = grant!(a, bot.founder, "profile.update", "/profile/bio")

      {a, expired} =
        grant!(a, bot.founder, "profile.update", "/profile/bio", %{"expires_at" => 4_000_000_000})

      {a, pending} =
        grant!(a, bot.founder, "profile.update", "/profile/bio", %{"not_before" => 4_000_000_000})

      Repo.get!(Grant, revoked.id)
      |> Ecto.Changeset.change(revoked_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      Repo.get!(Grant, expired.id)
      |> Ecto.Changeset.change(expires_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      assert status_of(a, active.id) == :active
      assert status_of(a, revoked.id) == :revoked
      assert status_of(a, expired.id) == :expired
      assert status_of(a, pending.id) == :pending
    end

    test "unieważnienie przodka przerywa łańcuch potomka", %{a: a, bot: bot} do
      carol = found!()
      {a, parent} = grant!(a, bot.founder, "profile.*", "/profile/*", %{"delegable" => true})

      body = %{
        "subject" => key_id(carol.founder),
        "action" => "profile.update",
        "resource" => a.id <> "/profile/bio",
        "parent_grant" => parent.id
      }

      {a, child} = next_event!(a, "grant.create", body, bot.founder)
      assert status_of(a, child.id) == :active

      Repo.get!(Grant, parent.id)
      |> Ecto.Changeset.change(revoked_at: ~U[2026-01-01 00:00:00Z])
      |> Repo.update!()

      assert status_of(a, parent.id) == :revoked
      assert status_of(a, child.id) == :broken
    end

    test "kolejność nadania i pola", %{a: a, bot: bot} do
      {a, first} = grant!(a, bot.founder, "profile.update", "/profile/bio")
      {a, second} = grant!(a, bot.founder, "project.*", "/lang/*", %{"delegable" => true})

      grants = Directory.grants(identity!(a.id))
      assert Enum.map(grants, & &1.id) |> Enum.sort() == Enum.sort([first.id, second.id])
      assert Enum.find(grants, &(&1.id == second.id)).delegable
      assert Enum.find(grants, &(&1.id == first.id)).subject_key_id == key_id(bot.founder)
    end
  end

  describe "timeline/2" do
    setup do
      a = found!(handle: "alfa")

      a =
        Enum.reduce(1..4, a, fn n, acc ->
          next!(acc, "profile.update", %{"fields" => %{"bio" => "v#{n}"}})
        end)

      {:ok, a: a}
    end

    test "najnowsze zdarzenia pierwsze, z typem, podpisującym i treścią", %{a: a} do
      {entries, next} = Directory.timeline(identity!(a.id))
      assert next == nil
      assert Enum.map(entries, & &1.seq) == [4, 3, 2, 1, 0]
      assert hd(entries).type == "profile.update"
      assert hd(entries).signer == key_id(a.founder)
      assert hd(entries).body == %{"fields" => %{"bio" => "v4"}}
      assert %DateTime{} = hd(entries).received_at
      assert List.last(entries).type == "identity.genesis"
    end

    test "strony: limit i before", %{a: a} do
      identity = identity!(a.id)

      {page1, next1} = Directory.timeline(identity, limit: 2)
      assert Enum.map(page1, & &1.seq) == [4, 3]
      assert next1 == 3

      {page2, next2} = Directory.timeline(identity, limit: 2, before: next1)
      assert Enum.map(page2, & &1.seq) == [2, 1]
      assert next2 == 1

      {page3, next3} = Directory.timeline(identity, limit: 2, before: next2)
      assert Enum.map(page3, & &1.seq) == [0]
      assert next3 == nil
    end

    test "uszkodzone zdarzenie jest oznaczone, a reszta nadal się czyta", %{a: a} do
      import Ecto.Query

      from(e in Event, where: e.identity_id == ^a.id and e.seq == 2)
      |> Repo.update_all(set: [signature: :binary.copy(<<0>>, 64)])

      {entries, _} = Directory.timeline(identity!(a.id))
      assert Enum.find(entries, &(&1.seq == 2)).corrupt
      refute Map.has_key?(Enum.find(entries, &(&1.seq == 3)), :corrupt)
    end
  end
end
