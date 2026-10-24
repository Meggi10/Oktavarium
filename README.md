# Oktavarium

**Oktavarium** to prototyp platformy dla osób twórczych i małych kolektywów.
Można tu prowadzić swój publiczny profil, pokazywać obrazy czy nagrania, tworzyć projekty oraz wspólnie publikować pliki.

Zamiast zwykłych kont opartych na haśle, aplikacja używa **kluczy kryptograficznych**.
Każda zmiana jest podpisywana i trafia do dziennika tożsamości.
Dzięki temu można sprawdzić historię zmian i określić, który klucz ma prawo zmienić stan danych.
**Oglądanie opublikowanych materiałów nie wymaga żadnej autoryzacji.**

## Co potrafi obecna wersja

- **Osoby i kolektywy:** tożsamości `person` i `collective`, z nazwą wyświetlaną, uchwytem `@handle`, opisem i zdjęciem profilowym.
- **Odkrywaj:** publiczny katalog osób, kolektywów, projektów, obrazów i nagrań.
- **Projekty:** osobne przestrzenie na pliki; projekt należy do tożsamości i zachowuje swoje ID po zmianie nazwy.
- **Pracownia:** edycja profilu, projekty, zasoby, uprawnienia, klucze i historia zmian.
- **Współpraca:** przyznawanie, delegowanie i cofanie uprawnień do określonych działań, projektów lub ścieżek.
- **Własne strony:** możliwość opublikowania plików HTML/CSS/JS, serwowanych pod osobnym hostem, jeśli instancja ma skonfigurowaną domenę stron.
- **Dzienniki:** podpisane zdarzenia oraz narzędzia do sprawdzenia i odbudowy aktualnego stanu bazy.

Tożsamość `unlisted` nie pojawia się w publicznym katalogu, 
ale nadal **można ją odczytać po bezpośrednim adresie**. 
Nie jest to tryb prywatny.

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
Testy tej wersji przeprowadzono na Elixirze 1.18.4 i Erlang/OTP 25.3.2.8.

Przy przebudowie całej warstwy skryptów przeglądarkowych potrzebne są także Node.js 
(co najmniej 20.19) i npm (`npm ci`, `npm run typecheck`, `npm run build`). 
Zbudowane pliki JS są już dołączone, więc samo uruchomienie serwera nie wymaga npm.

Baza to jeden plik SQLite, więc osobny serwer bazy danych nie jest potrzebny.
Treści i media są przechowywane osobno w katalogu blobów; kopia samej bazy nie wystarcza do odtworzenia publikacji.

### Środowisko

```sh
mix setup           # pobiera zależności, tworzy bazę sqlite i uruchamia migrację
mix phx.server      # serwer na http://localhost:4000
```

Pusta instancja pokazuje stronę z instrukcją założenia pierwszej tożsamości.
W środowisku rejestracja jest owarta, więc można to zrobić od razu
(klucze prywatne trafiają lokalnie do katalogu `keys/`, który jest w `.gitignore`):

```sh
mkdir -p keys events
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

### Najważniejsze adresy

| Adres | Co zawiera |
| --- | --- |
| `/` | Odkrywaj: publikacje i katalog społeczności. |
| `/?view=images`, `?view=audio`, `?view=projects`, `?view=people` | Filtry strony głównej. |
| `/i/:ref` | Publiczny profil osoby lub kolektywu. |
| `/i/:ref/projects/:project_id` | Publiczna strona projektu. |
| `/join` | Utworzenie tożsamości. |
| `/login` | Odblokowanie lub przywrócenie lokalnego skarbca. |
| `/studio` | Pracownia. |

### Testy

```sh
npm ci                              # przygotowanie lokalnych zależności TypeScript/LiveView
mix precommit                       # kompilacja, testy, typy TS, ESLint i build
npm audit --audit-level=moderate    # osobno: przegląd podatności npm
mix test                            # osobno: testy Elixira, z przygotowaniem bazy testowej
node --test test/js/*_test.mjs      # osobno: wbudowany mechanizm testowy Node.js
```

W `test/e2e` są też scenariusze testowe end-to-end dla przeglądarki.
Wymagają **uruchomionego serwera deweloperskiego**,
pakietu Python `playwright` i przeglądarki Chromium:

```sh
python3 test/e2e/browser_flow.py http://localhost:4000 /tmp/oktavarium-c2
python3 test/e2e/projects_flow.py http://localhost:4000 /tmp/oktavarium-projects-c2
```

**Uwaga:** 
testy E2E zakładają tożsamości i tworzą materiały na wskazanym serwerze. 
Nie uruchamiaj ich na ważnej bazie ani na produkcji.

### Polecenia operatora (praca bezpośrednio na bazie)

```sh
mix oktavarium.ingest events/ja-0.json  # wczytuje koperty do bazy z pominięciem HTTP
mix oktavarium.rebuild                  # sprawdza czy baza zgadza się z dziennikami
mix oktavarium.rebuild --apply          # odbudowuje projekcję z dzienników, jeśli się rozjechała
```

### Pierwsze kroki w przeglądarce

1. Wejdź na **`/join`** i utwórz tożsamość osoby lub kolektywu. Podaj uchwyt i osobną nazwę wyświetlaną.
2. Przygotuj klucze, pobierz **kopię skarbca** i zabezpiecz ją wraz z hasłem. Bez kluczy nie będzie można podpisywać zmian.
3. Otwórz **Pracownię** (`/studio`), wybierz tożsamość i odblokuj odpowiedni klucz.
4. Uzupełnij profil, utwórz projekt i opublikuj materiał. Przed zapisem zobaczysz podsumowanie operacji do podpisania.
5. Sprawdź rezultat na stronie głównej lub pod adresem profilu **`/i/TWOJ_UCHWYT`**.

Odblokowanie skarbca jest lokalne i **nie oznacza zalogowania na serwer**. Sesja serwerowa jest potrzebna osobno przy wysyłaniu bajtów plików. Samo przesłanie pliku nie jest jeszcze publikacją: potrzebne jest podpisane zdarzenie.

### Uruchomienie produkcyjne
Na produkcji (`MIX_ENV=prod`) wymagane są zmienne środowiskowe:

| Zmienna | Znaczenie |
| ------- | --------- |
| `DATABASE_PATH` | ścieżka pliku SQLite, np. `/var/lib/oktavarium/oktavarium.db` (**wymagana**) |
| `SECRET_KEY_BASE` | sekret serwera, wygeneruj `mix phx.gen.secret` (**wymagana**) |
| `PHX_HOST` | nazwa hosta (domyślnie `localhost`) |
| `PORT` | port HTTP (domyślnie `4000`) |
| `POOL_SIZE` | liczba połączeń z bazą (domyślnie `5`) |
| `OKTAVARIUM_REGISTRATION` | `open` albo `closed` (na produkcji domyślnie `closed`) |
| `OKTAVARIUM_BLOB_DIR` | Katalog magazynu plików; domyślnie `blobs` obok bazy. |
| `OKTAVARIUM_SITES_DOMAIN` | Osobna domena dla stron HTML/CSS/JS twórców; bez niej strony te są wyłączone. |

```sh
export MIX_ENV=prod
export DATABASE_PATH=/var/lib/oktavarium/oktavarium.db
export SECRET_KEY_BASE='TU_WSTAW_WYGENEROWANY_SEKRET'
export PHX_HOST=example.org

mix deps.get --only prod
mix ecto.create
mix ecto.migrate
mix phx.server
```

Na produkcji rejestracja nowych tożsamości przez HTTP jest domyślnie zamknięta. 
Operator może wystawić zaproszenie (`mix oktavarium.invite --uses 1 --days 7`),
wprowadzić przygotowane, podpisane zdarzenie za pomocą `mix oktavarium.ingest`
albo świadomie włączyć rejestrację. Token zaproszenia podaje się na `/join`
lub w nagłówku `X-Oktavarium-Invite` przy wysyłaniu genesis przez HTTP.
Własne strony powinny korzystać z oddzielnego hosta i odpowiednio skonfigurowanego DNS.
