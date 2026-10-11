defmodule Mix.Tasks.OktavariumTasksTest do
  # Mix.shell/1 jest globalne, więc testy nie mogą być asynchroniczne
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Oktavarium.{Cli, Envelope}
  alias Mix.Tasks.Oktavarium.{Event, Grant, Identity, Key, Profile}

  @moduletag :tmp_dir

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

  defp key_id!(path) do
    {:ok, %{id: id}} = Cli.show_key(path)
    id
  end

  test "pełny przepływ: klucze, tożsamość, grant, weryfikacja", %{tmp_dir: dir} do
    sign = Path.join(dir, "keys/sign.key")
    auth = Path.join(dir, "keys/auth.key")
    bot = Path.join(dir, "keys/bot.key")
    genesis = Path.join(dir, "events/0.json")
    grant = Path.join(dir, "events/1.json")

    Key.Gen.run(["--out", sign])
    assert infos() =~ "Wygenerowano klucz signing"
    Key.Gen.run(["--kind", "auth", "--out", auth])
    Key.Gen.run(["--out", bot])
    _ = infos()

    Key.Show.run([auth])
    assert infos() == "auth " <> key_id!(auth)

    Identity.Create.run([
      "--key",
      sign,
      "--kind",
      "person",
      "--handle",
      "pelagia",
      "--auth-key",
      key_id!(auth),
      "--out",
      genesis
    ])

    output = infos()
    assert output =~ "Tożsamość "
    assert output =~ "Klucz założycielski " <> key_id!(sign)
    refute output =~ "Uwaga"

    Grant.run([
      "--key",
      sign,
      "--after",
      genesis,
      "--to",
      key_id!(bot),
      "--action",
      "repo.push",
      "--expires",
      "2099-01-01",
      "--out",
      grant
    ])

    assert infos() =~ "repo.push na "

    Event.Verify.run([genesis, grant])
    output = infos()
    assert output =~ "OK #{genesis}: identity.genesis seq=0"
    assert output =~ "OK #{grant}: grant.create seq=1"
    assert output =~ "łańcuch spójny (zdarzeń: 2)"
  end

  test "klucze zaczynające się od myślnika działają jako wartości opcji", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    genesis = Path.join(dir, "0.json")
    dash_auth = Oktavarium.Crypto.encode(<<0xFB, 0::size(248)>>)
    dash_subject = Oktavarium.Crypto.encode(<<0xFB, 0xEF, 0::size(240)>>)

    Key.Gen.run(["--out", sign])

    Identity.Create.run([
      "--key",
      sign,
      "--kind",
      "person",
      "--auth-key",
      dash_auth,
      "--out",
      genesis
    ])

    Grant.run([
      "--key",
      sign,
      "--after",
      genesis,
      "--to",
      dash_subject,
      "--action",
      "a.b",
      "--out",
      Path.join(dir, "1.json")
    ])

    output = infos()
    assert output =~ "dla " <> dash_subject
    refute output =~ "Uwaga"
  end

  test "identity.create ostrzega, gdy nie podano klucza autoryzacji", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    Key.Gen.run(["--out", sign])
    _ = infos()

    Identity.Create.run([
      "--key",
      sign,
      "--kind",
      "collective",
      "--visibility",
      "unlisted",
      "--out",
      Path.join(dir, "g.json")
    ])

    assert infos() =~ "Uwaga: nie podano --auth-key"
  end

  test "bez --out koperta idzie na stdout, a komunikaty na stderr", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    Key.Gen.run(["--out", sign])
    _ = infos()

    stdout =
      capture_io(fn ->
        stderr =
          capture_io(:stderr, fn ->
            Identity.Create.run(["--key", sign, "--kind", "collective"])
          end)

        send(self(), {:stderr, stderr})
      end)

    assert_received {:stderr, stderr}
    assert stderr =~ "Tożsamość "

    assert {:ok, envelope} = stdout |> Jason.decode!() |> Envelope.from_map()
    assert {:ok, %{genesis?: true}} = Envelope.verify(envelope)
  end

  test "błędy kończą się Mix.Error z czytelnym komunikatem", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    Key.Gen.run(["--out", sign])
    _ = infos()

    assert_raise Mix.Error, ~r/już istnieje/, fn -> Key.Gen.run(["--out", sign]) end
    assert_raise Mix.Error, ~r/--out/, fn -> Key.Gen.run([]) end

    assert_raise Mix.Error, ~r/nieznana lub niekompletna opcja: --nope/, fn ->
      Key.Gen.run(["--nope"])
    end

    assert_raise Mix.Error, ~r/nieoczekiwane argumenty/, fn ->
      Key.Gen.run(["--out", sign, "x"])
    end

    assert_raise Mix.Error, ~r/--kind/, fn -> Identity.Create.run(["--key", sign]) end
    assert_raise Mix.Error, ~r/--after/, fn -> Grant.run(["--key", sign]) end
    assert_raise Mix.Error, ~r/dokładnie jeden plik/, fn -> Key.Show.run([]) end
    assert_raise Mix.Error, ~r/co najmniej jeden plik/, fn -> Event.Verify.run([]) end
  end

  test "event.verify zgłasza przerwany łańcuch", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    bot = Path.join(dir, "bot.key")
    [g, g1, g2] = for n <- 0..2, do: Path.join(dir, "#{n}.json")

    Key.Gen.run(["--out", sign])
    Key.Gen.run(["--out", bot])
    Identity.Create.run(["--key", sign, "--kind", "person", "--out", g])
    Grant.run(["--key", sign, "--after", g, "--to", key_id!(bot), "--action", "a.b", "--out", g1])

    Grant.run([
      "--key",
      sign,
      "--after",
      g1,
      "--to",
      key_id!(bot),
      "--action",
      "a.b",
      "--out",
      g2
    ])

    _ = infos()

    assert_raise Mix.Error, ~r/przerwany łańcuch zdarzeń \(seq_gap\)/, fn ->
      Event.Verify.run([g, g2])
    end
  end

  test "oktavarium.profile podpisuje zmianę profilu i łańcuch się weryfikuje", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    [g, p1, p2] = for n <- 0..2, do: Path.join(dir, "#{n}.json")

    Key.Gen.run(["--out", sign])
    Identity.Create.run(["--key", sign, "--kind", "person", "--out", g])
    _ = infos()

    Profile.run([
      "--key",
      sign,
      "--after",
      g,
      "--set",
      "display_name=Pelagia",
      "--set",
      "bio=a=b",
      "--unset",
      "location",
      "--out",
      p1
    ])

    output = infos()
    assert output =~ "Zmiana profilu "
    assert output =~ "Pola: bio, display_name, location"
    assert output =~ "Koperta zapisana w " <> p1

    Profile.run(["--key", sign, "--after", p1, "--set", "bio=nowe", "--out", p2])
    _ = infos()

    assert {:ok, [_, %{body: %{"fields" => fields}}, _]} = Cli.verify_files([g, p1, p2])
    assert fields == %{"display_name" => "Pelagia", "bio" => "a=b", "location" => nil}
  end

  test "oktavarium.profile: błędy kończą się Mix.Error", %{tmp_dir: dir} do
    sign = Path.join(dir, "sign.key")
    g = Path.join(dir, "0.json")
    Key.Gen.run(["--out", sign])
    Identity.Create.run(["--key", sign, "--kind", "person", "--out", g])
    _ = infos()

    assert_raise Mix.Error, ~r/--after/, fn -> Profile.run(["--key", sign, "--set", "bio=x"]) end

    assert_raise Mix.Error, ~r/co najmniej jedno --set/, fn ->
      Profile.run(["--key", sign, "--after", g])
    end

    assert_raise Mix.Error, ~r/niepoprawne pole profilu/, fn ->
      Profile.run(["--key", sign, "--after", g, "--set", "admin=x"])
    end

    assert_raise Mix.Error, ~r/więcej niż raz/, fn ->
      Profile.run(["--key", sign, "--after", g, "--set", "bio=a", "--unset", "bio"])
    end
  end
end
