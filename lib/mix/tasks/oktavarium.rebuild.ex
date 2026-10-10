defmodule Mix.Tasks.Oktavarium.Rebuild do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.{Cli, Replay}

  @impl Mix.Task
  def run(args) do
    Mix.Oktavarium.start_repo!()

    with {:ok, opts, _} <- Cli.parse_args(args, apply: :boolean),
         {:ok, report} <- Replay.run(apply: Keyword.get(opts, :apply, false)) do
      print(report)

      if not report.in_sync? and not report.applied? do
        Mix.raise("projekcja jest rozbieżna z dziennikami; uruchom ponownie z --apply")
      end
    else
      {:error, error} -> Mix.raise(format_error(error))
    end
  end

  defp print(report) do
    Mix.shell().info("Zdarzeń: #{report.events}, tożsamości: #{report.identities}")

    cond do
      report.in_sync? ->
        Mix.shell().info("Projekcja zgodna z dziennikami, nic do zrobienia.")

      true ->
        Mix.shell().info("Rozbieżności (tabela: brakuje / nadmiarowe / zmienione):")

        for {table, d} <- Enum.sort(report.drift),
            d.missing != [] or d.extra != [] or d.changed != [] do
          Mix.shell().info(
            "  #{table}: #{length(d.missing)} / #{length(d.extra)} / #{length(d.changed)}"
          )

          for {key, fields} <- Enum.take(d.changed, 5),
              do: Mix.shell().info("    zmienione #{inspect(key)}: #{Enum.join(fields, ", ")}")
        end

        if report.applied?, do: Mix.shell().info("Projekcja odbudowana z dzienników.")
    end
  end

  defp format_error({:corrupt, id, reason}),
    do: "uszkodzone zdarzenie #{id}: #{inspect(reason)}; baza nie została zmieniona"

  defp format_error({:stuck, stuck}) do
    list =
      stuck
      |> Enum.take(5)
      |> Enum.map_join(", ", fn {id, reason} -> "#{id} (#{inspect(reason)})" end)

    "nie da się odtworzyć #{length(stuck)} zdarzeń: #{list}; baza nie została zmieniona"
  end

  defp format_error(other) when is_binary(other), do: other
  defp format_error(other), do: Cli.format_error(other)
end
