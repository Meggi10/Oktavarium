defmodule Oktavarium.BlobsTest do
  use Oktavarium.DataCase

  alias Oktavarium.Blobs

  @png <<0x89, "PNG\r\n", 0x1A, "\n", "reszta pliku">>

  test "zapisuje blob pod hashem SHA-256 i ustala typ po bajtach" do
    assert {:ok, blob} = Blobs.put(@png, "image/png")
    assert blob.hash == :crypto.hash(:sha256, @png) |> Base.encode16(case: :lower)
    assert blob.media_type == "image/png"
    assert blob.size == byte_size(@png)
    assert Blobs.exists?(blob.hash)
    assert {:ok, path} = Blobs.path(blob.hash)
    assert File.read!(path) == @png
  end

  test "ten sam blob drugi raz to ten sam wiersz" do
    {:ok, a} = Blobs.put(@png, "image/png")
    {:ok, b} = Blobs.put(@png, "image/png")
    assert a.hash == b.hash
    assert Repo.aggregate(Oktavarium.Blobs.Blob, :count) == 1
  end

  test "typ zadeklarowany inaczej niż bajty: odrzucony" do
    assert {:error, :media_type_mismatch} = Blobs.put(@png, "audio/mpeg")
    assert {:error, :media_type_mismatch} = Blobs.put(@png, "text/html")
  end

  test "bez deklaracji typ wynika z bajtów; parametry nagłówka są ignorowane" do
    assert {:ok, %{media_type: "image/png"}} = Blobs.put(@png, nil)
    assert {:ok, %{media_type: "image/png"}} = Blobs.put(@png, "Image/PNG; charset=binary")
  end

  test "rozpoznaje formaty audio i obrazu" do
    cases = [
      {<<0xFF, 0xD8, 0xFF, 0xE0, 1, 2>>, "image/jpeg"},
      {"GIF89a....", "image/gif"},
      {"RIFF" <> <<0, 0, 0, 0>> <> "WEBPVP8 ", "image/webp"},
      {"RIFF" <> <<0, 0, 0, 0>> <> "WAVEfmt ", "audio/wav"},
      {"OggS" <> <<0, 2>>, "audio/ogg"},
      {"fLaC" <> <<0, 0>>, "audio/flac"},
      {"ID3" <> <<3, 0, 0>>, "audio/mpeg"},
      {<<0xFF, 0xFB, 0x90, 0>>, "audio/mpeg"},
      {<<0, 0, 0, 0x20>> <> "ftypM4A ", "audio/mp4"}
    ]

    for {bytes, type} <- cases, do: assert({:ok, %{media_type: ^type}} = Blobs.put(bytes, type))
  end

  test "tekst: tylko poprawny UTF-8 bez NUL i tylko dozwolone typy" do
    assert {:ok, %{media_type: "text/html"}} = Blobs.put("<h1>Cześć</h1>", "text/html")
    assert {:ok, %{media_type: "text/css"}} = Blobs.put("a{color:red}", "text/css")
    assert {:error, :media_type_mismatch} = Blobs.put(<<0xFF, 0xFE, 0x00>> <> "x", "text/html")
    assert {:error, :media_type_mismatch} = Blobs.put("a\0b", "text/plain")
    assert {:error, :unsupported_media_type} = Blobs.put("echo", "application/x-sh")
    assert {:error, :unsupported_media_type} = Blobs.put("echo", nil)
  end

  test "pusty i zbyt duży blob" do
    assert {:error, :empty} = Blobs.put(<<>>, "image/png")
    big = @png <> :binary.copy(<<0>>, Oktavarium.Resources.max_blob_size())
    assert {:error, :too_large} = Blobs.put(big, "image/png")
  end

  test "path/1 nie przyjmuje hasha spoza formatu (brak wyjścia z katalogu)" do
    assert {:error, :invalid_hash} = Blobs.path("../../etc/passwd")
    assert {:error, :invalid_hash} = Blobs.path(String.upcase(String.duplicate("a", 64)))
    assert nil == Blobs.get("nie-hash")
  end
end
