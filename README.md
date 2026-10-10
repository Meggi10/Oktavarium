# Oktavarium
Pseudo-anonimowa, samohostowalna platforma (z dostępem na zaproszenie) dla artystów, "nerdów" i ogółem społeczności,
oparta na **kryptograficznych tożsamościach** i **delegowanych uprawnieniach**.
Tożsamością jest klucz, uprawnienia to podpisane granty ("klucz A pozwala kluczowi B na X w Y do czasu Z"),
a każda tożsamość prowadzi własny, weryfikowalny dziennik podpisanych zdarzeń, podobny do historii commitów.
Tabele z bazie i strony WWW są jego widokiem, można je odbudować z dziennika.

## Dokumentacja
| Plik | Zawartość |
| ---- | --------- |
| [docs/01-project.md](docs/01-project.md) | temat, problem, grupa docelowa |
| [docs/02-requirements.md](docs/02-requirements.md) | procesy użytkownika, wymagania funkcjonalne (MVP i dodatkowe), role i uprawnienia |
| [docs/03-ux.md](docs/03-ux.md) | makiety widoków, spójność interfejsu, wymagania niefunkcjonalne |
| [docs/04-api.md](docs/04-api.md) | zaplecze danych, REST API, autoryzacja, ograniczenia |
| [docs/05-architecture.md](docs/05-architecture.md) | architektura, struktura projektu, stos, model danych (dzienniki, zdarzenia) |
| [docs/06-team-work.md](docs/06-team-work.md) | podział pracy, branche, PR, review |

## Autorzy
- *Magdalena Leśniewska* (u-20090)
- *Piotr Szymczak* (u-20714)

## Licencja
Projekt jest udostępniony na licencji **MIT**; pełny tekst w pliku [LICENSE](LICENSE).

## Uruchomienie

### Wymagania
Należy zainstalować `>=erlang::27.3.4` i `>=elixir::1.18.4` w środowisku:
[elixir-lang.org/install](https://elixir-lang.org/install/).

Baza to jeden plik SQLite, więc osobny serwer bazy danych nie jest potrzebny.

### Środowisko

```sh
mix setup           # pobiera zależności, tworzy bazę sqlite i uruchamia migrację
mix phx.server      # serwer na http://localhost:4000
```

Pusta instancja pokazuje stronę z instrukcją założenia pierwszej tożsamości.
W środowisku rejestracja jest owarta, więc można to zrobić od razu
(klucze prywatne trafiają lokalnie do katalogu `keys/`, który jest w `.gitignore`):

```sh
mix oktavarium.key.gen --out keys/ja.key                    # klucz sygnowania
mix oktavarium.key.gen --kind auth --out keys/laptop.key    # klucz autoryzacji
mix oktavarium.key.show keys/laptop.key                     # wypisuje id klucza (nigdy prywatny)

mix oktavarium.identity.create --key keys/ja.key --kind user --handle ja \
    --auth-key ID_KLUCZA_AUTH --out events/ja-0.json        # podpisuje zdarzenie założycielskie
mix oktavarium.submit events/ja-0.json                      # wysyła na http://localhost:4000

mix oktavarium.profile --key keys/ja.key --after events/ja-0.json \
    --set display_name=Ja --set 'bio=Czuję się troszeczkę jak Beethoven.' --out events/ja-1.json
mix oktavarium.submit events/ja-1.json
```

Tożsamość jest wtedy widoczna pod `http://localhost:4000/` i `http://localhost:4000/i/ja`.
Pozostałe polecenia (`oktavarium.grant`, `oktavarium.event.verify`) opisuje `mix help oktavarium.<nazwa>`,
a przebiegi od początku do końca [docs/02-requirements.md](docs/02-requirements.md).

### Testy

```sh
mix test            # przygotowuje bazę testową i uruchamia wszystkie testy
```

### Polecenia operatora (praca bezpośrednio na bazie)

```sh
mix oktavarium.ingest events/ja-0.json  # wczytuje koperty do bazy z pominięciem HTTP
mix oktavarium.rebuild                  # sprawdza czy baza zgadza się z dziennikami
mix oktavarium.rebuild --apply          # odbudowuje projekcję z dzienników, jeśli się rozjechała
```

### Uruchomienie produkcyjne
Na produkcji (`MIX_ENV=prod`) wymagane są zmienne środowiskowe:

| Zmienna | Znaczenie |
| ------- | --------- |
| `DATABASE_PATH` | ścieżka pliku SQLite, np. `/var/lib/oktavarium/oktavarium.db` (wymagana) |
| `SECRET_KEY_BASE` | sekret serwera, wygeneruj `mix phx.gen.secret` (wymagana) |
| `PHX_HOST` | nazwa hosta (domyślnie `localhost`) |
| `PORT` | port HTTP (domyślnie `4000`) |
| `POOL_SIZE` | liczba połączeń z bazą (domyślnie `5`) |
| `OKTAVARIUM_REGISTRACTION` | `open` albo `closed` (na produkcji domyślnie `closed`) |

```sh
export MIX_ENV=prod DATABASE_PATH=/var/lib/oktavarium/oktavarium.db SECRET_KEY_BASE=...
mix deps.get --only prod
mix ecto.create && mix ecto.migrate
mix phx.server
```

Przy `closed` nowe tożsamości przez HTTP są odrzucane;
pierwsze zdarzenia założycielskie wczytuje operator poleceniem `mix oktavarium.ingest`.
Serwer nie obsługuje TLS: należy go umieścić za serwerem pośredniczącym (reverse proxy) z HHTPS.
Gotowych wydań (release) i procedury kopii zapasowych nie ma.
