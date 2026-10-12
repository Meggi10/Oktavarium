defmodule Oktavarium.Log.ContentJournalTest do
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Blobs, Content, Envelope, Log, Replay}
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Resources.Resource

  test "tekst jest poza podpisanym payloadem i nie pojawia się w odtwarzanych kopertach" do
    a = found!()
    text = "Zażółć gęślą jaźń! prywatna wersja #{System.unique_integer([:positive])}"

    {a, ev} = next_event!(a, "profile.update", %{"fields" => %{"bio" => text}})
    hash = Content.hash(text)
    identity = Repo.get!(Identity, a.id)

    assert identity.profile["bio"] == text
    assert identity.profile_refs["bio"] == hash
    assert Blobs.read_text(hash) == {:ok, text}

    stored = Repo.get!(Oktavarium.Log.Event, ev.id)
    refute String.contains?(stored.payload, "Zażółć")
    assert String.contains?(stored.payload, hash)

    [_, envelope] = Log.envelopes(a.id)
    assert envelope.attachments == %{}

    assert {:ok, %{body: %{"fields" => %{"bio" => %{"sha256" => ^hash}}}}} =
             Envelope.verify(envelope)

    assert :ok = Log.verify(a.id)
  end

  test "zmiana/usunięcie treści zwalnia stary blob; weryfikacja i replay nie potrzebują jego bajtów" do
    a = found!()
    old = "Wersja do usunięcia #{System.unique_integer([:positive])}"
    a = next!(a, "profile.update", %{"fields" => %{"bio" => old}})
    old_hash = Content.hash(old)

    assert {:error, :in_use} = Blobs.prune_orphan(old_hash)

    a = next!(a, "profile.update", %{"fields" => %{"bio" => "Nowa wersja"}})
    assert :ok = Blobs.prune_orphan(old_hash)
    assert :missing = Blobs.read_text(old_hash)
    assert :ok = Log.verify(a.id)
    assert {:ok, %{in_sync?: true}} = Replay.run()
    assert Repo.get!(Identity, a.id).profile["bio"] == "Nowa wersja"

    a = next!(a, "profile.update", %{"fields" => %{"bio" => nil}})
    assert Repo.get!(Identity, a.id).profile == %{}
    assert Repo.get!(Identity, a.id).profile_refs == %{}
    assert :ok = Log.verify(a.id)
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "załączniki są kontrolowane przez hash, nie można podmienić tekstu po podpisaniu" do
    a = found!()
    bytes = "Niepowtarzalny opis #{System.unique_integer([:positive])}"

    envelope =
      Envelope.sign(
        %{
          type: "profile.update",
          identity: a.id,
          seq: a.seq + 1,
          prev: a.head,
          body: %{"fields" => %{"bio" => bytes}}
        },
        a.founder
      )

    assert [{hash, ^bytes}] = Map.to_list(envelope.attachments)
    bad = %{envelope | attachments: %{hash => "INNA TREŚĆ"}}
    assert {:error, {:invalid_envelope, :invalid_attachments}} = Log.append(bad)
    assert {:error, {:content_missing, ^hash}} = Log.append(%{envelope | attachments: %{}})
    assert {:ok, %{seq: 1}} = Log.append(envelope)
  end

  test "zmiana slugu bez nowych metadanych zachowuje skróty tytułu projektu" do
    a = found!()

    {a, created} =
      next_event!(a, "project.create", %{
        "slug" => "pierwszy",
        "meta" => %{"title" => "Tytuł projektu"}
      })

    _a = next!(a, "project.update", %{"id" => created.id, "slug" => "drugi"})

    project = Repo.get!(Resource, created.id)
    assert project.path == "projects/drugi"
    assert project.meta == %{"title" => "Tytuł projektu"}
    assert project.meta_refs == %{"title" => Content.hash("Tytuł projektu")}
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "opisy projektów i plików mają oddzielne referencje, ale czytelne projekcje" do
    a = found!()

    {a, project} =
      next_event!(a, "project.create", %{
        "slug" => "notatki",
        "meta" => %{"title" => "Nasze notatki", "description" => "Opis kolektywu"}
      })

    _a =
      next!(a, "resource.put", %{
        "path" => "images/plakat.png",
        "hash" => String.duplicate("a", 64),
        "size" => 123,
        "media_type" => "image/png",
        "project_id" => project.id,
        "meta" => %{"alt" => "Plakat"}
      })

    p = Repo.get!(Resource, project.id)
    assert p.meta == %{"title" => "Nasze notatki", "description" => "Opis kolektywu"}
    assert p.meta_refs["title"] == Content.hash("Nasze notatki")

    assert [%Resource{meta: %{"alt" => "Plakat"}, meta_refs: %{"alt" => hash}}] =
             Repo.all(from r in Resource, where: r.project_id == ^project.id)

    assert hash == Content.hash("Plakat")
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end
end
