defmodule Oktavarium.CryptoTest do
  use ExUnit.Case, async: true

  alias Oktavarium.Crypto

  setup do
    {:ok, kp: Crypto.generate_keypair()}
  end

  test "podpis i weryfikacja", %{kp: kp} do
    sig = Crypto.sign(:event, "hello", kp.private)
    assert byte_size(sig) == 64
    assert Crypto.verify(:event, "hello", sig, kp.public)
  end

  test "zmieniona wiadomość, zły klucz albo uszkodzony podpis nie przechodzą", %{kp: kp} do
    other = Crypto.generate_keypair()
    sig = Crypto.sign(:event, "hello", kp.private)

    refute Crypto.verify(:event, "hellO", sig, kp.public)
    refute Crypto.verify(:event, "hello", sig, other.public)

    <<first, rest::binary>> = sig
    refute Crypto.verify(:event, "hello", <<Bitwise.bxor(first, 1), rest::binary>>, kp.public)
  end

  test "separacja domen: podpis logowania nie jest podpisem zdarzenia", %{kp: kp} do
    sig = Crypto.sign(:login, "challenge", kp.private)
    assert Crypto.verify(:login, "challenge", sig, kp.public)
    refute Crypto.verify(:event, "challenge", sig, kp.public)
  end

  test "dane spoza zaufania nie powodują wyjątku", %{kp: kp} do
    refute Crypto.verify(:event, "m", "krótki", kp.public)
    refute Crypto.verify(:event, "m", :crypto.strong_rand_bytes(64), "krótki")
    refute Crypto.verify(:event, "m", nil, kp.public)
  end

  test "identyfikator klucza to odwracalne kodowanie klucza publicznego", %{kp: kp} do
    id = Crypto.key_id(kp.public)
    assert is_binary(id) and String.length(id) == 43
    assert Crypto.decode_key_id(id) == {:ok, kp.public}
    assert Crypto.decode_key_id("za-krótki") == :error
    assert Crypto.decode_key_id("!!!") == :error
  end

  test "event_hash jest deterministyczny i zależy od danych" do
    assert Crypto.event_hash("a") == Crypto.event_hash("a")
    refute Crypto.event_hash("a") == Crypto.event_hash("b")
    assert byte_size(Crypto.event_hash("a")) == 32
  end
end
