defmodule Oktavarium.Cli.Files do
  @moduledoc false
  # Zapis plików, który nigdy nie nadpisuje istniejących, oraz odczyt ze spójnym
  # kształtem błędów: `{:exists, path}` albo `{:file, path, posix}`.

  @spec write_new(Path.t(), iodata(), non_neg_integer()) :: :ok | {:error, term()}
  def write_new(path, content, mode) do
    with :ok <- tag(File.mkdir_p(Path.dirname(path)), path),
         {:ok, io} <- open_exclusive(path) do
      result =
        try do
          # uprawnienia ustawiamy zanim trafi do pliku jakakolwiek treść
          with :ok <- tag(File.chmod(path, mode), path) do
            tag(IO.binwrite(io, content), path)
          end
        after
          File.close(io)
        end

      if result != :ok, do: File.rm(path)
      result
    end
  end

  @spec read(Path.t()) :: {:ok, binary()} | {:error, term()}
  def read(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file, path, reason}}
    end
  end

  defp open_exclusive(path) do
    case File.open(path, [:write, :exclusive, :binary]) do
      {:ok, io} -> {:ok, io}
      {:error, :eexist} -> {:error, {:exists, path}}
      {:error, reason} -> {:error, {:file, path, reason}}
    end
  end

  defp tag(:ok, _path), do: :ok
  defp tag({:error, reason}, path), do: {:error, {:file, path, reason}}
end
