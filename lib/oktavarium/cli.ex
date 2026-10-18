defmodule Oktavarium.Cli do
  @moduledoc false
  alias Oktavarium.{Capability, Crypto, Envelope, Projects, Resources}
  alias Oktavarium.Cli.{Files, Keyfile}
  alias Oktavarium.Identities.{Profile, Rules}

  @type result :: {:ok, map()} | {:error, term()}

  # parsowanie argumentów

  @doc """
  Parsuje argumenty wiersza poleceń ścisłym `OptionParser`.

  Z `allow_args: true` zwraca też argumenty pozycyjne; bez niego każdy argument
  pozycyjny jest błędem.
  """
  @spec parse_args([String.t()], keyword(), keyword()) ::
          {:ok, keyword(), [String.t()]} | {:error, term()}
  def parse_args(args, switches, opts \\ []) do
    case OptionParser.parse(join_dash_values(args, switches), strict: switches) do
      {parsed, rest, []} ->
        if rest == [] or Keyword.get(opts, :allow_args, false) do
          {:ok, parsed, rest}
        else
          {:error, {:unexpected_args, rest}}
        end

      {_parsed, _rest, [{flag, _value} | _]} ->
        {:error, {:unknown_option, flag}}
    end
  end

  # Identyfikatory kluczy to base64url, więc mogą zaczynać się od "-" (a nawet "--").
  # `OptionParser` wziąłby taką wartość za kolejną opcję, więc przed parsowaniem
  # sklejamy `--opcja -wartość` w `--opcja=-wartość`. Nie definiujemy aliasów
  # jednoznakowych, więc token z jednym myślnikiem nigdy nie jest opcją; token z
  # dwoma jest opcją tylko wtedy, gdy jej nazwa jest znana.
  defp join_dash_values(args, switches) do
    known = Enum.map(switches, fn {name, _type} -> flag_name(name) end)

    string_flags =
      for {name, type} <- switches, :string in List.wrap(type), do: flag_name(name)

    do_join(args, known, string_flags)
  end

  defp do_join([flag, value | rest], known, string_flags)
       when is_binary(flag) and is_binary(value) do
    if flag in string_flags and String.starts_with?(value, "-") and
         not known_flag?(value, known) do
      [flag <> "=" <> value | do_join(rest, known, string_flags)]
    else
      [flag | do_join([value | rest], known, string_flags)]
    end
  end

  defp do_join([arg | rest], known, string_flags), do: [arg | do_join(rest, known, string_flags)]
  defp do_join([], _known, _string_flags), do: []

  defp known_flag?("--" <> _ = value, known),
    do: value |> String.split("=", parts: 2) |> hd() |> then(&(&1 in known))

  defp known_flag?(_value, _known), do: false

  defp flag_name(name), do: "--" <> (name |> Atom.to_string() |> String.replace("_", "-"))

  # klucze

  @doc "Generuje klucz (`\"signing\"` albo `\"auth\"`) i zapisuje go w `out` (bez nadpisywania)."
  @spec gen_key(String.t() | nil, String.t() | nil) :: result()
  def gen_key(kind, out) do
    with {:ok, out} <- require_opt(out, :out),
         {:ok, kind} <- parse_key_kind(kind),
         key = Keyfile.generate(kind),
         :ok <- Keyfile.write_new(out, key) do
      {:ok, %{id: Keyfile.id(key), kind: kind, path: out}}
    end
  end

  @doc "Odczytuje plik klucza i zwraca jego publiczny identyfikator i rodzaj (nigdy klucz prywatny)."
  @spec show_key(Path.t()) :: result()
  def show_key(path) do
    with {:ok, key} <- Keyfile.read(path) do
      {:ok, %{id: Keyfile.id(key), kind: key.kind}}
    end
  end

  # zdarzenia

  @doc """
  Podpisuje zdarzenie genesis, które zakłada tożsamość.

  Opcje: `:kind` (wymagana), `:visibility` (public/unlisted), `:handle`,
  `:auth_keys` (lista id kluczy autoryzacji).
  Podpisuje klucz `:signing` z `key_path`; staje się on kluczem założycielskim.
  """
  @spec create_identity(Path.t(), keyword()) :: result()
  def create_identity(key_path, opts) do
    with {:ok, key} <- load_signing_key(key_path),
         {:ok, kind} <- identity_kind(opts[:kind]),
         {:ok, visibility} <- identity_visibility(opts[:visibility]),
         {:ok, handle} <- identity_handle(opts[:handle]),
         {:ok, auth_keys} <- validate_key_ids(Keyword.get(opts, :auth_keys, [])) do
      body =
        %{"kind" => Atom.to_string(kind)}
        |> put_unless_nil("visibility", visibility)
        |> put_unless_nil("handle", handle)
        |> put_unless_empty("auth_keys", auth_keys)

      finish(Envelope.genesis(body, Keyfile.keypair(key)))
    end
  end

  @doc """
  Podpisuje zdarzenie `grant.create`: klucz podpisujący pozwala kluczowi `:to` na
  `:action` na `:resource`.

  Opcje: `:after` (plik poprzedniego zdarzenia tożsamości, wymagana), `:to` (id klucza,
  wymagana), `:action` (wymagana), `:resource` (domyślnie `"<id tożsamości>/*"`),
  `:not_before`, `:expires_at` (ISO 8601 albo sama data, w UTC), `:parent_grant`
  (id grantu, na którego podstawie wystawia klucz inny niż założycielski),
  `:delegable` (czy podmiot może przekazywać uprawnienie dalej).

  CLI sprawdza tylko to, co da się sprawdzić bez stanu serwera: składnię wzorców,
  to, że zasób należy do tej tożsamości, i okno czasowe. Czy podpisujący ma prawo
  wystawić taki grant (łańcuch grantów, attenuation względem jego własnych
  uprawnień), rozstrzyga serwer (`Oktavarium.Authz`).
  """
  @spec create_grant(Path.t(), keyword()) :: result()
  def create_grant(key_path, opts) do
    with {:ok, key} <- load_signing_key(key_path),
         {:ok, after_path} <- require_opt(opts[:after], :after),
         {:ok, prev} <- read_event(after_path),
         {:ok, to} <- require_key_id(opts[:to], :to),
         {:ok, action} <- require_opt(opts[:action], :action),
         :ok <- check(Capability.valid_action?(action), {:invalid_action, action}),
         {:ok, resource} <- grant_resource(prev.identity, opts),
         :ok <- check(Capability.valid_resource?(resource), {:invalid_resource, resource}),
         :ok <-
           check(
             Capability.in_identity?(resource, prev.identity),
             {:resource_outside_identity, resource, prev.identity}
           ),
         {:ok, not_before} <- parse_time(opts[:not_before], :not_before),
         {:ok, expires_at} <- parse_time(opts[:expires_at], :expires_at),
         :ok <- check_window(not_before, expires_at),
         {:ok, parent_grant} <- optional_id(opts[:parent_grant], :parent_grant) do
      body =
        %{"subject" => to, "action" => action, "resource" => resource}
        |> put_unless_nil("not_before", not_before)
        |> put_unless_nil("expires_at", expires_at)
        |> put_unless_nil("parent_grant", parent_grant)
        |> then(&if(opts[:delegable] == true, do: Map.put(&1, "delegable", true), else: &1))

      %{
        type: "grant.create",
        seq: prev.seq + 1,
        identity: prev.identity,
        prev: prev.id,
        body: body
      }
      |> Envelope.sign(Keyfile.keypair(key))
      |> finish()
    end
  end

  defp grant_resource(identity, opts) do
    case opts[:project] do
      nil -> {:ok, opts[:resource] || identity <> "/*"}
      project -> Projects.grant_resource(identity, project, opts[:resource] || "*")
    end
  end

  @doc "Prepare and sign a project operation without writing to the database."
  def project_event(key_path, operation, opts) when operation in ["create", "update", "delete"] do
    body =
      %{}
      |> put_unless_nil("id", opts[:id])
      |> put_unless_nil("slug", opts[:slug])

    meta =
      %{}
      |> put_unless_nil("title", opts[:title])
      |> put_unless_nil("description", opts[:description])

    body =
      if operation == "create" or map_size(meta) > 0, do: Map.put(body, "meta", meta), else: body

    sign_operation(key_path, "project." <> operation, body, opts[:after])
  end

  def project_event(_key_path, operation, _opts),
    do: {:error, {:invalid_option, :operation, operation}}

  @doc "Prepare resource.put/delete. --root explicitly clears project_id; omission preserves it."
  def resource_event(key_path, operation, opts) when operation in ["put", "delete"] do
    with :ok <-
           check(
             not (opts[:root] == true and not is_nil(opts[:project])),
             {:invalid_body, "project_id"}
           ) do
      body =
        %{}
        |> put_unless_nil("id", opts[:id])
        |> put_unless_nil("path", opts[:path])
        |> put_unless_nil("project_id", opts[:project])
        |> put_unless_nil("hash", opts[:hash])
        |> put_unless_nil("size", opts[:size])
        |> put_unless_nil("media_type", opts[:media_type])

      body = if opts[:root] == true, do: Map.put(body, "project_id", nil), else: body

      meta =
        Enum.reduce([:title, :alt, :description, :collection], %{}, fn field, acc ->
          put_unless_nil(acc, Atom.to_string(field), opts[field])
        end)

      body = if map_size(meta) > 0, do: Map.put(body, "meta", meta), else: body
      sign_operation(key_path, "resource." <> operation, body, opts[:after])
    end
  end

  def resource_event(_key_path, operation, _opts),
    do: {:error, {:invalid_option, :operation, operation}}

  def revoke_grant(key_path, opts) do
    with {:ok, id} <- require_opt(opts[:grant], :grant),
         :ok <- check(Resources.valid_id?(id), {:invalid_body, "grant"}) do
      sign_operation(key_path, "grant.revoke", %{"grant" => id}, opts[:after])
    end
  end

  defp sign_operation(key_path, type, body, after_path) do
    with {:ok, key} <- load_signing_key(key_path),
         {:ok, after_path} <- require_opt(after_path, :after),
         {:ok, prev} <- read_event(after_path),
         {:ok, _} <- validate_operation(type, body) do
      Envelope.sign(
        %{type: type, seq: prev.seq + 1, identity: prev.identity, prev: prev.id, body: body},
        Keyfile.keypair(key)
      )
      |> finish()
    end
  end

  defp validate_operation("project.create", body), do: Projects.parse_create(body)
  defp validate_operation("project.update", body), do: Projects.parse_update(body)
  defp validate_operation("project.delete", body), do: Projects.parse_delete(body)
  defp validate_operation("resource.put", body), do: Resources.parse_put(body)
  defp validate_operation("resource.delete", body), do: Resources.parse_delete(body)
  defp validate_operation("grant.revoke", body), do: {:ok, body}

  @doc """
  Podpisuje zdarzenie `profile.update`: ustawia albo usuwa pola profilu tożsamości.

  Opcje: `:after` (plik poprzedniego zdarzenia tożsamości, wymagana), `:set` (lista
  napisów `"pole=wartość"`; wartość może zawierać `=`) i `:unset` (lista nazw pól do
  usunięcia). Trzeba podać co najmniej jedno pole, a to samo pole nie może być
  jednocześnie ustawiane i usuwane ani podane dwa razy.

  CLI sprawdza pola i wartości (`Oktavarium.Identities.Profile`). Czy podpisujący ma
  prawo zmienić dane pole (klucz założycielski albo grant `profile.update` na
  `<id>/profile/<pole>`), rozstrzyga serwer.
  """
  @spec update_profile(Path.t(), keyword()) :: result()
  def update_profile(key_path, opts) do
    with {:ok, key} <- load_signing_key(key_path),
         {:ok, after_path} <- require_opt(opts[:after], :after),
         {:ok, prev} <- read_event(after_path),
         {:ok, set} <- parse_assignments(Keyword.get(opts, :set, [])),
         unset = Keyword.get(opts, :unset, []),
         {:ok, changes} <- merge_profile_changes(set, unset),
         {:ok, changes} <- validate_profile_changes(changes) do
      %{
        type: "profile.update",
        seq: prev.seq + 1,
        identity: prev.identity,
        prev: prev.id,
        body: %{"fields" => changes}
      }
      |> Envelope.sign(Keyfile.keypair(key))
      |> finish()
    end
  end

  defp parse_assignments(assignments) do
    Enum.reduce_while(assignments, {:ok, []}, fn assignment, {:ok, acc} ->
      case String.split(assignment, "=", parts: 2) do
        [field, value] when field != "" -> {:cont, {:ok, [{field, value} | acc]}}
        _other -> {:halt, {:error, {:invalid_option, :set, assignment}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp merge_profile_changes(set, unset) do
    fields = Enum.map(set, &elem(&1, 0)) ++ unset

    case {fields, first_duplicate(fields)} do
      {[], _} -> {:error, :no_profile_changes}
      {_, nil} -> {:ok, Map.merge(Map.new(unset, &{&1, nil}), Map.new(set))}
      {_, dup} -> {:error, {:duplicate_field, dup}}
    end
  end

  defp first_duplicate(list) do
    {_seen, dup} =
      Enum.reduce_while(list, {MapSet.new(), nil}, fn item, {seen, nil} ->
        if MapSet.member?(seen, item),
          do: {:halt, {seen, item}},
          else: {:cont, {MapSet.put(seen, item), nil}}
      end)

    dup
  end

  defp validate_profile_changes(changes) do
    case Profile.parse_changes(changes) do
      {:ok, changes} -> {:ok, changes}
      {:error, {:invalid_body, path}} -> {:error, {:invalid_profile_field, path}}
    end
  end

  # pliki kopert

  @doc "Koperta jako JSON do zapisania lub wyświetlenia."
  @spec encode_envelope(Envelope.t()) :: String.t()
  def encode_envelope(%Envelope{} = envelope) do
    envelope |> Envelope.to_map() |> Jason.encode!(pretty: true)
  end

  @doc "Zapisuje kopertę do nowego pliku (bez nadpisywania)."
  @spec write_envelope(Path.t(), Envelope.t()) :: :ok | {:error, term()}
  def write_envelope(path, %Envelope{} = envelope) do
    Files.write_new(path, encode_envelope(envelope) <> "\n", 0o644)
  end

  @doc "Zapisuje kopertę do `path`, a bez ścieżki wypisuje ją na standardowe wyjście."
  @spec output_envelope(Envelope.t(), Path.t() | nil) :: :ok | {:error, term()}
  def output_envelope(envelope, nil), do: IO.puts(encode_envelope(envelope))
  def output_envelope(envelope, path), do: write_envelope(path, envelope)

  @doc "Wczytuje plik koperty bez interpretowania jej treści (podpis sprawdza dopiero odbiorca)."
  @spec read_envelope(Path.t()) :: {:ok, Envelope.t()} | {:error, term()}
  def read_envelope(path) do
    with {:ok, raw} <- Files.read(path),
         {:ok, map} <- decode_json(raw, path) do
      envelope_from_map(map, path)
    end
  end

  @doc """
  Wysyła koperty z plików na serwer (`POST <url>/api/events`), po kolei i w podanej
  kolejności, bo zdarzenia jednego dziennika muszą dotrzeć w kolejności `seq`.
  Zatrzymuje się na pierwszym błędzie. Opcja `:post` (funkcja `url, json -> {:ok,
  status, body} | {:error, powód}`) pozwala podmienić transport w testach.

  Zwraca `{:ok, [%{path:, id:, identity:, seq:}]}` albo
  `{:error, {:submit_failed, path, status, kod_błędu}}`.
  """
  @spec submit([Path.t()], String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def submit([], _url, _opts), do: {:error, :no_files}

  def submit(paths, url, opts) do
    post = Keyword.get(opts, :post, &Oktavarium.Cli.Http.post_json/2)
    endpoint = String.trim_trailing(url, "/") <> "/api/events"

    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      with {:ok, envelope} <- read_envelope(path),
           {:ok, result} <- post_envelope(post, endpoint, envelope, path) do
        {:cont, {:ok, [Map.put(result, :path, path) | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp post_envelope(post, endpoint, envelope, path) do
    json = envelope |> Envelope.to_map() |> Jason.encode!()

    case post.(endpoint, json) do
      {:ok, 201, body} ->
        case Jason.decode(body) do
          {:ok, %{"id" => id, "identity" => identity, "seq" => seq}} ->
            {:ok, %{id: id, identity: identity, seq: seq}}

          _ ->
            {:error, {:submit_failed, path, 201, "nieczytelna odpowiedź serwera"}}
        end

      {:ok, status, body} ->
        {:error, {:submit_failed, path, status, error_code(body)}}

      {:error, reason} ->
        {:error, {:unreachable, endpoint, reason}}
    end
  end

  defp error_code(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"code" => code} = error}} ->
        extra = error |> Map.drop(["code"]) |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
        if extra == "", do: code, else: code <> " (" <> extra <> ")"

      _ ->
        "odpowiedź bez kodu błędu"
    end
  end

  @doc "Wczytuje plik koperty i weryfikuje jego podpis oraz strukturę."
  @spec read_event(Path.t()) :: {:ok, Envelope.event()} | {:error, term()}
  def read_event(path) do
    with {:ok, raw} <- Files.read(path),
         {:ok, map} <- decode_json(raw, path),
         {:ok, envelope} <- envelope_from_map(map, path),
         {:ok, event} <- verify_envelope(envelope, path) do
      {:ok, event}
    end
  end

  @doc """
  Weryfikuje pliki kopert. Przy kilku plikach sprawdza też, że tworzą spójny
  łańcuch w podanej kolejności: ta sama tożsamość, `seq` rosnący o 1, `prev`
  wskazujący poprzednie zdarzenie, a genesis tylko na początku.
  """
  @spec verify_files([Path.t()]) :: {:ok, [Envelope.event()]} | {:error, term()}
  def verify_files([]), do: {:error, :no_files}

  def verify_files(paths) do
    result =
      Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
        with {:ok, event} <- read_event(path),
             :ok <- check_link(acc, event, path) do
          {:cont, {:ok, [event | acc]}}
        else
          error -> {:halt, error}
        end
      end)

    with {:ok, events} <- result, do: {:ok, Enum.reverse(events)}
  end

  # komunikaty o błędach

  @doc "Komunikat o błędzie czytelny dla człowieka."
  @spec format_error(term()) :: String.t()
  def format_error({:file, path, reason}),
    do: "plik #{path}: #{reason |> :file.format_error() |> to_string()}"

  def format_error({:exists, path}), do: "#{path} już istnieje; nie nadpisuję"
  def format_error(:invalid_keyfile), do: "to nie jest poprawny plik klucza Oktavarium"
  def format_error(:key_mismatch), do: "klucz publiczny w pliku nie pasuje do prywatnego"
  def format_error(:no_files), do: "podaj co najmniej jeden plik koperty"
  def format_error({:unknown_option, flag}), do: "nieznana lub niekompletna opcja: #{flag}"

  def format_error({:unexpected_args, rest}),
    do: "nieoczekiwane argumenty: #{Enum.join(rest, " ")}"

  def format_error({:missing_option, name}), do: "brak wymaganej opcji #{flag(name)}"

  def format_error({:invalid_option, name, value}),
    do: "niepoprawna wartość opcji #{flag(name)}: #{inspect(value)}"

  def format_error({:wrong_key_kind, expected}),
    do: "ta operacja wymaga klucza rodzaju #{expected}"

  def format_error({:invalid_key_id, id}), do: "niepoprawny identyfikator klucza: #{inspect(id)}"

  def format_error({:invalid_time, name, value}),
    do: "niepoprawny czas w #{flag(name)}: #{inspect(value)} (ISO 8601, np. 2027-01-01)"

  def format_error(:invalid_window), do: "--expires musi być późniejsze niż --not-before"

  def format_error({:ingest_failed, path, reason}),
    do: "#{path}: baza odrzuciła zdarzenie (#{inspect(reason)})"

  def format_error({:submit_failed, path, status, code}),
    do: "#{path}: serwer odrzucił zdarzenie (HTTP #{status}: #{code})"

  def format_error({:unreachable, endpoint, reason}),
    do: "nie można połączyć się z #{endpoint}: #{inspect(reason)}"

  def format_error(:no_profile_changes),
    do: "podaj co najmniej jedno --set pole=wartość albo --unset pole"

  def format_error({:duplicate_field, field}),
    do: "pole #{inspect(field)} podano więcej niż raz (--set i --unset razem też się wykluczają)"

  def format_error({:invalid_profile_field, "fields"}), do: "niepoprawne zmiany profilu"

  def format_error({:invalid_profile_field, "fields." <> field}),
    do:
      "niepoprawne pole profilu albo jego wartość: #{field} " <>
        "(dozwolone pola: #{Enum.join(Profile.fields(), ", ")}; wartość niepusta, w limicie długości)"

  def format_error({:invalid_action, action}), do: "niepoprawny wzorzec akcji: #{inspect(action)}"

  def format_error({:invalid_resource, resource}),
    do: "niepoprawny wzorzec zasobu: #{inspect(resource)}"

  def format_error({:resource_outside_identity, resource, identity}),
    do: "zasób #{inspect(resource)} musi zaczynać się od id tożsamości #{identity}"

  def format_error({:invalid_envelope, path, reason}),
    do: "#{path}: niepoprawna koperta (#{inspect(reason)})"

  def format_error({:broken_chain, path, reason}),
    do: "#{path}: przerwany łańcuch zdarzeń (#{reason})"

  def format_error(other), do: "błąd: #{inspect(other)}"

  # wewnętrzne

  defp flag(name), do: flag_name(name)

  defp finish(envelope) do
    case Envelope.verify(envelope) do
      {:ok, event} -> {:ok, %{envelope: envelope, event: event}}
      {:error, reason} -> {:error, {:invalid_envelope, "(nowe zdarzenie)", reason}}
    end
  end

  defp load_signing_key(nil), do: {:error, {:missing_option, :key}}

  defp load_signing_key(path) do
    case Keyfile.read(path) do
      {:ok, %{kind: :signing} = key} -> {:ok, key}
      {:ok, _auth_key} -> {:error, {:wrong_key_kind, :signing}}
      {:error, _} = error -> error
    end
  end

  defp parse_key_kind("signing"), do: {:ok, :signing}
  defp parse_key_kind("auth"), do: {:ok, :auth}
  defp parse_key_kind(value), do: {:error, {:invalid_option, :kind, value}}

  defp identity_visibility(nil), do: {:ok, nil}

  defp identity_visibility(value) do
    case Rules.parse_visibility(value) do
      {:ok, visibility} -> {:ok, Atom.to_string(visibility)}
      :error -> {:error, {:invalid_option, :visibility, value}}
    end
  end

  defp identity_kind(nil), do: {:error, {:missing_option, :kind}}

  defp identity_kind(value) do
    case Rules.parse_kind(value) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, {:invalid_option, :kind, value}}
    end
  end

  defp identity_handle(nil), do: {:ok, nil}

  defp identity_handle(handle) do
    if Rules.valid_handle?(handle),
      do: {:ok, handle},
      else: {:error, {:invalid_option, :handle, handle}}
  end

  defp require_opt(nil, name), do: {:error, {:missing_option, name}}
  defp require_opt(value, _name), do: {:ok, value}

  defp require_key_id(nil, name), do: {:error, {:missing_option, name}}

  defp require_key_id(id, _name) do
    case Crypto.decode_key_id(id) do
      {:ok, _public} -> {:ok, id}
      :error -> {:error, {:invalid_key_id, id}}
    end
  end

  defp optional_id(nil, _name), do: {:ok, nil}

  defp optional_id(id, name) do
    case Crypto.decode(id) do
      {:ok, <<_::binary-size(32)>>} -> {:ok, id}
      _ -> {:error, {:invalid_option, name, id}}
    end
  end

  defp validate_key_ids(ids) do
    ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case require_key_id(id, :auth_key) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp parse_time(nil, _name), do: {:ok, nil}

  defp parse_time(value, name) when is_binary(value) do
    with {:error, _} <- datetime_unix(value),
         {:error, _} <- date_unix(value) do
      {:error, {:invalid_time, name, value}}
    end
  end

  defp datetime_unix(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_unix(datetime)}
      {:error, _} = error -> error
    end
  end

  defp date_unix(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()}
      {:error, _} = error -> error
    end
  end

  defp check_window(not_before, expires_at)
       when is_integer(not_before) and is_integer(expires_at) and expires_at <= not_before,
       do: {:error, :invalid_window}

  defp check_window(_not_before, _expires_at), do: :ok

  defp check(true, _error), do: :ok
  defp check(false, error), do: {:error, error}

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp put_unless_empty(map, _key, []), do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  defp decode_json(raw, path) do
    case Jason.decode(raw) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:error, {:invalid_envelope, path, :invalid_json}}
    end
  end

  defp envelope_from_map(map, path) do
    case Envelope.from_map(map) do
      {:ok, envelope} -> {:ok, envelope}
      {:error, reason} -> {:error, {:invalid_envelope, path, reason}}
    end
  end

  defp verify_envelope(envelope, path) do
    case Envelope.verify(envelope) do
      {:ok, event} -> {:ok, event}
      {:error, reason} -> {:error, {:invalid_envelope, path, reason}}
    end
  end

  # pierwszy plik może być genesis albo dowolnym zdarzeniem łańcucha
  defp check_link([], _event, _path), do: :ok

  defp check_link([prev | _], event, path) do
    cond do
      event.genesis? -> {:error, {:broken_chain, path, :unexpected_genesis}}
      event.identity != prev.identity -> {:error, {:broken_chain, path, :identity_mismatch}}
      event.seq != prev.seq + 1 -> {:error, {:broken_chain, path, :seq_gap}}
      event.prev != prev.id -> {:error, {:broken_chain, path, :prev_mismatch}}
      true -> :ok
    end
  end
end
