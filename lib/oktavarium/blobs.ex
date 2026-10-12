defmodule Oktavarium.Blobs do
  @moduledoc false
  import Ecto.Query, only: [from: 2]
  alias Oktavarium.{Content, Repo, Resources}
  alias Oktavarium.Blobs.Blob
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Resources.Resource

  @text_types ~w(text/html text/css text/javascript text/plain application/json image/svg+xml)

  @doc "Katalog z bajtami blobów (`config :oktavarium, :blob_dir`)."
  def dir, do: Application.fetch_env!(:oktavarium, :blob_dir)

  @doc "Ścieżka pliku bloba; `{:error, :invalid_hash}` dla hasha w złym formacie."
  @spec path(String.t()) :: {:ok, Path.t()} | {:error, :invalid_hash}
  def path(hash) do
    if Resources.valid_hash?(hash),
      do: {:ok, Path.join([dir(), String.slice(hash, 0, 2), String.slice(hash, 2..-1//1)])},
      else: {:error, :invalid_hash}
  end

  @doc """
  Zapisuje bajty. `declared` to typ zadeklarowany przez klienta (nagłówek
  `content-type`). Zwraca `{:ok, %Blob{}}` albo `{:error, powód}`:
  `:empty`, `:too_large`, `:unsupported_media_type`, `:media_type_mismatch`.
  """
  @spec put(binary(), String.t() | nil) :: {:ok, Blob.t()} | {:error, atom()}
  def put(bytes, declared) when is_binary(bytes) do
    with :ok <- check_size(bytes),
         {:ok, media_type} <- detect(bytes, normalize(declared)) do
      hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      {:ok, file} = path(hash)

      with :ok <- write_file(file, bytes) do
        {:ok, upsert(hash, byte_size(bytes), media_type)}
      end
    end
  end

  @doc "Metadane bloba albo `nil`."
  @spec get(String.t()) :: Blob.t() | nil
  def get(hash) when is_binary(hash), do: Repo.get(Blob, hash)
  def get(_other), do: nil

  @doc "Czyta krótką treść UTF-8 po skrócie albo zwraca :missing."
  @spec read_text(String.t()) :: {:ok, String.t()} | :missing
  def read_text(hash) do
    with %Blob{size: size} when size <= 10_000 <- get(hash),
         {:ok, file} <- path(hash),
         {:ok, bytes} <- File.read(file),
         true <- String.valid?(bytes) and byte_size(bytes) <= 10_000,
         true <- Content.hash(bytes) == hash do
      {:ok, bytes}
    else
      _ -> :missing
    end
  end

  @doc """
  Usuwa nieużywane bajty (GC operatora, nie publiczny endpoint).
  W pierwszej kolejności trzeba podpisać zmianę/usunięcie referencji.
  Skróty historyczne pozostają w niezmiennym dzienniku. Funkcja odmawia
  usunięcia bloba wskazywanego przez dowolną AKTUALNĄ projekcję.
  """
  @spec prune_orphan(String.t()) :: :ok | {:error, atom()}
  def prune_orphan(hash) do
    with true <- Resources.valid_hash?(hash),
         false <- currently_referenced?(hash),
         {:ok, file} <- path(hash) do
      case File.rm(file) do
        :ok -> Repo.delete_all(from b in Blob, where: b.hash == ^hash)
        {:error, :enoent} -> Repo.delete_all(from b in Blob, where: b.hash == ^hash)
        {:error, _} -> :error
      end
      |> case do
        :error -> {:error, :storage}
        _ -> :ok
      end
    else
      false -> {:error, :invalid_hash}
      true -> {:error, :in_use}
      _ -> {:error, :invalid_hash}
    end
  end

  defp currently_referenced?(hash) do
    Repo.exists?(from r in Resource, where: r.hash == ^hash) or
      Enum.any?(Repo.all(from i in Identity, select: i.profile_refs), fn refs ->
        hash in Map.values(refs || %{})
      end) or
      Enum.any?(Repo.all(from r in Resource, select: r.meta_refs), fn refs ->
        hash in Map.values(refs || %{})
      end)
  end

  @spec exists?(String.t()) :: boolean()
  def exists?(hash) do
    case path(hash) do
      {:ok, file} -> File.regular?(file)
      _ -> false
    end
  end

  @doc """
  Wykrywanie typu: `{:ok, media_type}` albo błąd. Wywoływane też z testów.
  """
  @spec detect(binary(), String.t() | nil) :: {:ok, String.t()} | {:error, atom()}
  def detect(bytes, declared) do
    case sniff(bytes) do
      {:ok, sniffed} ->
        if declared in [nil, sniffed] or compatible?(declared, sniffed),
          do: {:ok, sniffed},
          else: {:error, :media_type_mismatch}

      :none ->
        if declared in @text_types and text?(bytes),
          do: {:ok, declared},
          else:
            {:error,
             if(declared in Resources.all_media_types(),
               do: :media_type_mismatch,
               else: :unsupported_media_type
             )}
    end
  end

  # kontenery ogg/mp4 bywają deklarowane różnie; wystarczy ten sam rodzaj
  defp compatible?("audio/x-wav", "audio/wav"), do: true
  defp compatible?("audio/mp3", "audio/mpeg"), do: true
  defp compatible?("audio/x-flac", "audio/flac"), do: true
  defp compatible?("audio/x-m4a", "audio/mp4"), do: true
  defp compatible?("audio/aac", "audio/mp4"), do: true
  defp compatible?("image/vnd.microsoft.icon", "image/x-icon"), do: true
  defp compatible?(_declared, _sniffed), do: false

  defp sniff(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: ok("image/png")
  defp sniff(<<0xFF, 0xD8, 0xFF, _::binary>>), do: ok("image/jpeg")
  defp sniff(<<"GIF87a", _::binary>>), do: ok("image/gif")
  defp sniff(<<"GIF89a", _::binary>>), do: ok("image/gif")
  defp sniff(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: ok("image/webp")
  defp sniff(<<"RIFF", _::binary-size(4), "WAVE", _::binary>>), do: ok("audio/wav")
  defp sniff(<<"OggS", _::binary>>), do: ok("audio/ogg")
  defp sniff(<<"fLaC", _::binary>>), do: ok("audio/flac")
  defp sniff(<<"ID3", _::binary>>), do: ok("audio/mpeg")
  # ramka MPEG audio: 11 bitów synchronizacji
  defp sniff(<<0xFF, b, _::binary>>) when b >= 0xE0, do: ok("audio/mpeg")
  defp sniff(<<_::binary-size(4), "ftyp", _::binary>>), do: ok("audio/mp4")
  defp sniff(<<"wOFF", _::binary>>), do: ok("font/woff")
  defp sniff(<<"wOF2", _::binary>>), do: ok("font/woff2")
  defp sniff(<<0, 0, 1, 0, _::binary>>), do: ok("image/x-icon")
  defp sniff(_other), do: :none

  defp ok(type), do: {:ok, type}

  defp text?(bytes), do: String.valid?(bytes) and not String.contains?(bytes, <<0>>)

  defp normalize(nil), do: nil

  defp normalize(declared) when is_binary(declared) do
    declared |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()
  end

  defp check_size(<<>>), do: {:error, :empty}

  defp check_size(bytes),
    do: if(byte_size(bytes) > Resources.max_blob_size(), do: {:error, :too_large}, else: :ok)

  defp write_file(file, bytes) do
    if File.regular?(file) do
      :ok
    else
      tmp = file <> ".#{System.unique_integer([:positive])}.tmp"

      with :ok <- File.mkdir_p(Path.dirname(file)),
           :ok <- File.write(tmp, bytes),
           :ok <- File.rename(tmp, file) do
        :ok
      else
        {:error, reason} ->
          File.rm(tmp)
          {:error, {:storage, reason}}
      end
    end
  end

  defp upsert(hash, size, media_type) do
    Repo.insert!(%Blob{hash: hash, size: size, media_type: media_type},
      on_conflict: :nothing,
      conflict_target: :hash
    )

    Repo.get!(Blob, hash)
  end
end
