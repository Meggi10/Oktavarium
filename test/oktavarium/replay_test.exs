defmodule Oktavarium.ReplayTest do
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Log, Replay}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.Key
  alias Oktavarium.Log.Event

  # Dwie tożsamości; druga dostaje od pierwszej grant na bio, zmienia bio w jej
  # dzienniku i profil własnej tożsamości zmienia właściciel.
  defp populate! do
    a = found!(handle: "pelagia")
    b = found!(handle: "aleksandra")

    {a, _} = grant!(a, b.founder, "profile.update", "/profile/bio")
    a = next!(a, "profile.update", %{"fields" => %{"display_name" => "Pelagia"}})
    a = next!(a, "profile.update", %{"fields" => %{"bio" => "od Aleksandry"}}, b.founder)
    b = next!(b, "profile.update", %{"fields" => %{"location" => "Gdańsk"}})
    %{a: a, b: b}
  end

  defp event_ids(identity_id) do
    Repo.all(from e in Event, where: e.identity_id == ^identity_id, order_by: e.seq, select: e.id)
  end

  describe "run/1" do
    test "pusta baza jest zgodna" do
      assert {:ok, %{events: 0, identities: 0, in_sync?: true, applied?: false}} = Replay.run()
    end

    test "poprawna baza jest zgodna i nic się nie zmienia" do
      %{a: a} = populate!()
      before = Replay.snapshot()

      assert {:ok, %{events: 6, identities: 2, in_sync?: true, applied?: false}} =
               Replay.run(apply: true)

      assert Replay.snapshot() == before
      assert :ok = Log.verify(a.id)
    end

    test "sprawdzanie pokazuje rozbieżności i niczego nie zmienia" do
      %{a: a} = populate!()

      Repo.update_all(from(i in Identity, where: i.id == ^a.id),
        set: [profile: %{"bio" => "podmienione"}]
      )

      Repo.delete_all(Grant)
      drifted = Replay.snapshot()

      assert {:ok, report} = Replay.run()
      refute report.in_sync?
      refute report.applied?
      assert [{a_id, [:profile]}] = report.drift.identities.changed
      assert a_id == a.id
      assert [_grant_id] = report.drift.grants.missing
      assert Replay.snapshot() == drifted
    end

    test "--apply naprawia projekcję" do
      %{a: a, b: b} = populate!()
      good = Replay.snapshot()

      Repo.update_all(from(i in Identity, where: i.id == ^a.id), set: [profile: %{}])
      Repo.delete_all(Grant)

      Repo.update_all(from(k in Key, where: k.id == ^Oktavarium.Fixtures.key_id(b.founder)),
        set: [status: :revoked]
      )

      refute Replay.snapshot() == good

      assert {:ok, %{in_sync?: false, applied?: true}} = Replay.run(apply: true)
      assert Replay.snapshot() == good
      assert {:ok, %{in_sync?: true}} = Replay.run()
      assert :ok = Log.verify(a.id)
      assert :ok = Log.verify(b.id)
    end

    test "naprawia zmienione pola tożsamości, zdarzenia zostają" do
      %{a: a} = populate!()
      good = Replay.snapshot()
      ids = event_ids(a.id)

      # `events` trzyma klucze obce, więc zamiast kasować projekcję rozbieżność robimy przez ręczne zmiany
      Repo.update_all(Identity, set: [handle: nil, kind: :collective, visibility: :unlisted])

      assert {:ok, %{applied?: true}} = Replay.run(apply: true)
      assert Replay.snapshot() == good
      assert event_ids(a.id) == ids
    end

    test "ręczna zmiana spoza dzienników jest rozbieżnością" do
      %{a: a} = populate!()
      Repo.update_all(from(i in Identity, where: i.id == ^a.id), set: [visibility: :unlisted])

      assert {:ok, %{in_sync?: false, drift: %{identities: %{changed: [{id, [:visibility]}]}}}} =
               Replay.run()

      assert id == a.id
    end

    test "przy odbudowie przywraca widoczność zmienioną podpisanym zdarzeniem" do
      a = found!(handle: "alfa")
      a = next!(a, "identity.visibility.set", %{"visibility" => "unlisted"})
      assert Repo.get!(Identity, a.id).visibility == :unlisted

      Repo.update_all(from(i in Identity, where: i.id == ^a.id), set: [visibility: :public])

      assert {:ok, %{in_sync?: false, drift: %{identities: %{changed: [{id, [:visibility]}]}}}} =
               Replay.run()

      assert id == a.id
      assert {:ok, %{applied?: true}} = Replay.run(apply: true)
      assert Repo.get!(Identity, a.id).visibility == :unlisted
      assert {:ok, %{in_sync?: true}} = Replay.run()
    end

    test "zachowuje czas przyjęcia zdarzeń i wierszy" do
      %{a: a} = populate!()
      past = ~N[2026-01-02 03:04:05]
      Repo.update_all(Event, set: [inserted_at: past])
      Repo.update_all(from(i in Identity, where: i.id == ^a.id), set: [profile: %{}])

      assert {:ok, %{applied?: true}} = Replay.run(apply: true)

      assert Repo.all(from e in Event, select: e.inserted_at) |> Enum.uniq() == [past]
      assert Repo.get!(Identity, a.id).inserted_at == past
      assert Repo.one(from g in Grant, select: g.inserted_at) == past
    end

    test "uprawnienia ocenia się względem czasu przyjęcia, nie względem teraz" do
      a = found!()
      b = found!()
      soon = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()

      {a, _} = grant!(a, b.founder, "profile.update", "/profile/bio", %{"expires_at" => soon})
      a = next!(a, "profile.update", %{"fields" => %{"bio" => "w terminie"}}, b.founder)

      assert {:ok, %{in_sync?: true}} = Replay.run()

      # zdarzenie przyjęte "po wygaśnięciu grantu" nie byłoby dziś poprawne
      late =
        NaiveDateTime.utc_now() |> NaiveDateTime.add(2 * 3600) |> NaiveDateTime.truncate(:second)

      Repo.update_all(from(e in Event, where: e.id == ^a.head), set: [inserted_at: late])

      assert {:error, {:stuck, [{id, {:not_authorized, "bio"}}]}} = Replay.run(apply: true)
      assert id == a.head
    end

    test "zdarzenie zależne od późniejszego z innego dziennika zostaje odłożone, nie odrzucone" do
      %{b: b} = populate!()
      good = Replay.snapshot()

      # genesis delegata wypada na koniec: grant na jego klucz trzeba odłożyć na drugi przebieg
      late =
        NaiveDateTime.utc_now() |> NaiveDateTime.add(86_400) |> NaiveDateTime.truncate(:second)

      Repo.update_all(from(e in Event, where: e.id == ^b.id), set: [inserted_at: late])

      assert {:ok, %{in_sync?: true}} = Replay.run(apply: true)
      assert Replay.snapshot() == good
    end

    test "uszkodzone zdarzenie przerywa odbudowę bez zmian w bazie" do
      %{a: a} = populate!()
      Repo.update_all(from(i in Identity, where: i.id == ^a.id), set: [profile: %{}])
      before = Replay.snapshot()
      [_genesis, victim | _] = event_ids(a.id)

      Repo.update_all(from(e in Event, where: e.id == ^victim),
        set: [payload: "{\"zepsute\":true}"]
      )

      assert {:error, {:corrupt, ^victim, _reason}} = Replay.run(apply: true)
      assert Replay.snapshot() == before
    end

    test "dziura w dzienniku kończy się błędem i niczego nie zmienia" do
      %{a: a} = populate!()
      before = Replay.snapshot()
      [_genesis, hole, after_hole | _] = event_ids(a.id)

      Repo.delete_all(from e in Event, where: e.id == ^hole)

      assert {:error, {:stuck, stuck}} = Replay.run(apply: true)
      assert {^after_hole, {:bad_seq, 1}} = List.keyfind(stuck, after_hole, 0)
      assert Replay.snapshot() == before
      assert Repo.exists?(from e in Event, where: e.id == ^after_hole)
    end
  end

  describe "diff/2" do
    test "brakujące, nadmiarowe i zmienione wiersze" do
      before = %{t: %{"a" => %{x: 1, y: 1}, "b" => %{x: 1, y: 1}}}
      after_ = %{t: %{"b" => %{x: 2, y: 1}, "c" => %{x: 1, y: 1}}}

      assert %{t: %{missing: ["c"], extra: ["a"], changed: [{"b", [:x]}]}} =
               Replay.diff(before, after_)
    end
  end
end
