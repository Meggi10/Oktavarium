defmodule Oktavarium.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Oktavarium.{Crypto, Envelope}

  setup do
    {:ok, kp: Crypto.generate_keypair()}
  end

  describe "genesis" do
    test "tworzy tożsamość o identyfikatorze równym skrótowi zdarzenia", %{kp: kp} do
      env = Envelope.genesis(%{"kind" => "person", "handle" => "pelagia"}, kp)

      assert {:ok, event} = Envelope.verify(env)
      assert event.genesis?
      assert event.seq == 0
      assert event.prev == nil
      assert event.type == "identity.genesis"
      assert event.identity == event.id
      assert event.id == Envelope.id(env)
      assert event.signer == Crypto.key_id(kp.public)
      assert event.body == %{"kind" => "person", "handle" => "pelagia"}
    end

    test "identyfikator zależy od treści i klucza założycielskiego", %{kp: kp} do
      other = Crypto.generate_keypair()
      attrs = %{type: "identity.genesis", seq: 0, body: %{"kind" => "person"}, ts: 1_700_000_000}

      a = Envelope.sign(attrs, kp)
      same = Envelope.sign(attrs, kp)
      other_body = Envelope.sign(%{attrs | body: %{"kind" => "collective"}}, kp)
      other_key = Envelope.sign(attrs, other)

      # deterministyczne: ten sam klucz i ładunek dają ten sam identyfikator
      assert Envelope.id(a) == Envelope.id(same)
      assert Envelope.id(a) != Envelope.id(other_body)
      # klucz założycielski jest częścią ładunku, więc nie da się "przejąć" cudzego
      # identyfikatora, powtarzając treść genesis własnym kluczem
      assert Envelope.id(a) != Envelope.id(other_key)
    end

    test "genesis z seq != 0 jest odrzucany", %{kp: kp} do
      env = Envelope.sign(%{type: "identity.genesis", seq: 1, identity: nil, prev: nil}, kp)
      assert Envelope.verify(env) == {:error, :invalid_genesis}
    end
  end

  describe "zdarzenia zwykłe" do
    test "łańcuch: kolejne zdarzenie wskazuje tożsamość i poprzednika", %{kp: kp} do
      genesis = Envelope.genesis(%{"kind" => "collective"}, kp)
      identity = Envelope.id(genesis)

      env =
        Envelope.sign(
          %{
            type: "profile.update",
            seq: 1,
            identity: identity,
            prev: identity,
            body: %{"bio" => "x"}
          },
          kp
        )

      assert {:ok, event} = Envelope.verify(env)
      refute event.genesis?
      assert event.identity == identity
      assert event.prev == identity
      assert event.seq == 1
    end

    test "zdarzenie bez tożsamości albo poprzednika jest odrzucane", %{kp: kp} do
      env = Envelope.sign(%{type: "profile.update", seq: 1, identity: nil, prev: nil}, kp)
      assert Envelope.verify(env) == {:error, :invalid_chain_fields}

      env = Envelope.sign(%{type: "profile.update", seq: 0, identity: "x", prev: "y"}, kp)
      assert Envelope.verify(env) == {:error, :invalid_chain_fields}
    end
  end

  describe "integralność" do
    test "zmiana ładunku unieważnia podpis", %{kp: kp} do
      env = Envelope.genesis(%{"kind" => "person"}, kp)
      tampered = %{env | payload: String.replace(env.payload, "person", "admn")}
      assert Envelope.verify(tampered) == {:error, :bad_signature}
    end

    test "podmiana klucza podpisującego unieważnia podpis", %{kp: kp} do
      env = Envelope.genesis(%{"kind" => "person"}, kp)
      other = Crypto.generate_keypair()
      assert Envelope.verify(%{env | signer: other.public}) == {:error, :bad_signature}
    end

    test "podpis pod inną domeną nie jest akceptowany jako podpis zdarzenia", %{kp: kp} do
      env = Envelope.genesis(%{"kind" => "person"}, kp)
      forged = %{env | signature: Crypto.sign(:login, env.payload, kp.private)}
      assert Envelope.verify(forged) == {:error, :bad_signature}
    end
  end

  describe "ładunki zniekształcone, ale poprawnie podpisane" do
    defp signed(payload, kp) do
      %Envelope{
        payload: payload,
        signer: kp.public,
        signature: Crypto.sign(:event, payload, kp.private)
      }
    end

    test "klucz zadeklarowany w ładunku inny niż faktycznie podpisujący", %{kp: kp} do
      other = Crypto.generate_keypair()

      payload =
        Jason.encode!(%{
          "v" => 2,
          "signer" => Crypto.key_id(other.public),
          "type" => "x",
          "seq" => 1,
          "identity" => "a",
          "prev" => "b",
          "body" => %{},
          "ts" => 1
        })

      assert Envelope.verify(signed(payload, kp)) == {:error, :signer_mismatch}
    end

    test "nie-JSON", %{kp: kp} do
      assert Envelope.verify(signed("to nie json", kp)) == {:error, :invalid_json}
    end

    test "nieobsługiwana wersja", %{kp: kp} do
      payload = Jason.encode!(%{"v" => 3, "type" => "x", "seq" => 0, "body" => %{}, "ts" => 1})
      assert Envelope.verify(signed(payload, kp)) == {:error, :unsupported_version}
    end

    test "brakujące pola", %{kp: kp} do
      payload = Jason.encode!(%{"v" => 2, "type" => "x"})
      assert Envelope.verify(signed(payload, kp)) == {:error, :invalid_payload}
    end

    test "zły typ pola identity", %{kp: kp} do
      payload =
        Jason.encode!(%{
          "v" => 2,
          "type" => "x",
          "seq" => 1,
          "body" => %{},
          "ts" => 1,
          "identity" => 5
        })

      assert Envelope.verify(signed(payload, kp)) == {:error, {:invalid_field, "identity"}}
    end
  end

  describe "postać sieciowa" do
    test "to_map/from_map przez JSON zachowuje podpisane bajty", %{kp: kp} do
      env = Envelope.genesis(%{"kind" => "person", "handle" => "zażółć"}, kp)

      wire = env |> Envelope.to_map() |> Jason.encode!() |> Jason.decode!()
      assert {:ok, decoded} = Envelope.from_map(wire)

      assert decoded == env
      assert {:ok, _event} = Envelope.verify(decoded)
    end

    test "zniekształcone koperty" do
      assert Envelope.from_map(%{}) == {:error, :malformed}

      assert Envelope.from_map(%{"payload" => "!", "signer" => "x", "signature" => "y"}) ==
               {:error, :malformed}

      assert Envelope.from_map("nie mapa") == {:error, :malformed}
    end
  end
end
