defmodule Mix.Tasks.OktavariumRebuildTest do
  # Mix.shell/1 jest globalne, a baza używa piaskownicy w trybie współdzielonym
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.Identities.Identity
  alias Mix.Tasks.Oktavarium.Rebuild

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp infos(acc \\ []) do
    receive do
      {:mix_shell, :info, [message]} -> infos([message | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  test "zgodna baza: raport i kod sukcesu" do
    a = found!(handle: "pelagia")
    next!(a, "profile.update", %{"fields" => %{"bio" => "x"}})

    Rebuild.run([])

    out = infos()
    assert out =~ "Zdarzeń: 2, tożsamości: 1"
    assert out =~ "zgodna"
  end

  test "rozbieżność bez --apply kończy się błędem, z --apply naprawia" do
    a = found!(handle: "pelagia")
    next!(a, "profile.update", %{"fields" => %{"bio" => "x"}})
    Repo.update_all(from(i in Identity, where: i.id == ^a.id), set: [profile: %{}])

    assert_raise Mix.Error, ~r/--apply/, fn -> Rebuild.run([]) end
    assert infos() =~ "identities: 0 / 0 / 1"
    assert Repo.get!(Identity, a.id).profile == %{}

    Rebuild.run(["--apply"])
    assert infos() =~ "odbudowana"
    assert Repo.get!(Identity, a.id).profile == %{"bio" => "x"}
  end

  test "uszkodzone zdarzenie: czytelny błąd" do
    a = found!()
    Repo.update_all(Oktavarium.Log.Event, set: [signature: <<0::512>>])

    assert_raise Mix.Error, ~r/uszkodzone zdarzenie #{a.id}.*nie została zmieniona/, fn ->
      Rebuild.run(["--apply"])
    end
  end

  test "nieznana opcja" do
    assert_raise Mix.Error, ~r/--nope/, fn -> Rebuild.run(["--nope"]) end
  end
end
