defmodule Oktavarium.Cli.Http do
  @moduledoc false

  @spec post_json(String.t(), String.t()) :: {:ok, pos_integer(), binary()} | {:error, term()}
  def post_json(url, json) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), [], ~c"application/json", json}

    http_options = [
      timeout: 15_000,
      connect_timeout: 5_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]

    case :httpc.request(:post, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end
end
