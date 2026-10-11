defmodule Oktavarium.JsInteropTest do
  @moduledoc false
  use Oktavarium.DataCase

  alias Oktavarium.{Crypto, Envelope, Log}

  @script Path.expand("../js/emit_envelopes.mjs", __DIR__)
  @moduletag skip: if(System.find_executable("node"), do: false, else: "brak node")

  setup do
    message = "oktavarium.test\nnonce-123"
    {out, 0} = System.cmd("node", [@script, message])
    {:ok, data: Jason.decode!(out), message: message}
  end

  test "genesis i zdarzenie podpisane w JS przechodzą przez Log.append", %{data: d} do
    {:ok, genesis} = Envelope.from_map(d["genesis"])
    assert {:ok, event} = Log.append(genesis)
    assert event.id == d["genesisId"]
    assert event.identity == d["genesisId"]

    {:ok, update} = Envelope.from_map(d["update"])
    assert {:ok, %{seq: 1, type: "profile.update"}} = Log.append(update)

    identity = Repo.get!(Oktavarium.Identities.Identity, d["genesisId"])
    assert identity.profile["bio"] =~ "Zażółć"
    assert identity.handle == "z-przegladarki"
    assert identity.kind == :person
    assert :ok = Log.verify(d["genesisId"])
  end

  test "podpis logowania z JS weryfikuje się w domenie :login i tylko w niej", %{
    data: d,
    message: m
  } do
    {:ok, public} = Crypto.decode_key_id(d["auth"])
    {:ok, login} = Crypto.decode(d["loginSig"])
    {:ok, event_sig} = Crypto.decode(d["eventSig"])

    assert Crypto.verify(:login, m, login, public)
    refute Crypto.verify(:event, m, login, public)
    assert Crypto.verify(:event, m, event_sig, public)
    refute Crypto.verify(:login, m, event_sig, public)
  end

  test "identyfikator zdarzenia liczony w JS zgadza się z serwerowym" do
    expected = Crypto.event_hash("x") |> Crypto.encode()
    {out, 0} = System.cmd("node", [@script])
    assert Jason.decode!(out)["idCheck"] == expected
  end
end
