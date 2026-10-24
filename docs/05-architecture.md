# 05. Architektura

Dokument opisuje architekturę aplikacji (stos, strukturę projektu, biblioteki, stan, komunikację)
oraz model danych tożsamości, uprawnień i dzienników zdarzeń.
Kod jest źródłem prawdy; ten plik tłumaczy, **dlaczego** jest tak, a nie inaczej.
Część od sekcji "Model domeny" w dół to rozwinięta wersja wcześniejszego dokumentu o modelu platformy.

## Przegląd

Oktavarium to jedna aplikacja Elixir (OTP) o trzech warstwach. Zależności idą tylko w dół.

```
  przeglądarka lub CLI                           operator (mix oktavarium.ingest / rebuild)
       |  HTTP / JSON / podpisane koperty                     |  bezpośrednio do bazy
       v                                                      v
+----------------------------------------------------+   +-------------------------+
| Warstwa webowa  OktavariumWeb.*                    |   | Zadania Mix             |
|  Endpoint -> Router -> kontrolery / widoki HEEx    |   |  Mix.Tasks.Oktavarium.* |
+--------------------------+-------------------------+   +----------+--------------+
                           |                                        |
                           v                                        v
+-----------------------------------------------------------------------------+
| Warstwa domeny / projekcji                                                  |
|  Log (append, verify, head, envelopes)   Replay (odbudowa)   Directory      |
|  Log.Planner + Authz (czysta logika decyzji)       Ecto: Repo + schematy    |
+--------------------------+--------------------------------------------------+
                           |
                           v
+-----------------------------------------------------------------------------+
| Rdzeń bez bazy: Crypto, Envelope, Capability, Delegation, Identities.Rules, |
| Identities.Profile — czyste funkcje, testowane bez bazy                     |
+-----------------------------------------------------------------------------+
                           |
                           v
                  SQLite (jeden plik): events (źródło prawdy) + projekcja
```

Zasada przewodnia: **decyzje są w czystych funkcjach** (`Planner`, `Authz`), 
a `Log` tylko ładuje fakty z bazy i zapisuje wynik.
Dzięki temu reguły da się testować bez bazy,
a odbudowa projekcji (`Replay`) używa tego samego plannera co zwykłe przyjęcie zdarzenia.

## Framework i stos technologiczny

| Element | Wersja | Rola |
| ------- | ------ | ---- |
| Elixir / Erlang OTP | wymagane `~> 1.17` (mix.exs); rozwijane i testowane na Elixir 1.18.4, OTP 27 | język i platforma uruchomieniowa |
| Phoenix | `~> 1.8` (testowano 1.8.15) | framework webowy: endpoint, router, kontrolery |
| Phoenix HTML, Phoenix LiveView | `~> 4.2` (4.3.0), `~> 1.1` (1.2.12) | gniazda LiveView, szablony HEEx i komponenty funkcyjne; |
| Bandit | `~> 1.13.1` (1.13.1) | serwer HTTP |
| Ecto SQL + Ecto SQLite3 | `~> 3.14` (3.14.2 / 3.14.0), `~> 0.25` (0.25.0) | dostęp do bazy, migracje, schematy |
| Exqlite | 0.42.0 (zależność Ecto SQLite3) | sterownik SQLite |
| Jason | `~> 1.4` (1.4.5) | JSON |
| `:crypto`, `:public_key`, `:ssl`, `:inets` (OTP) | z OTP | Ed25519 i skróty; klient HTTP z weryfikacją TLS w CLI |

Wersje w nawiasach to wersje, na których uruchomiono pełny zestaw testów.

### Dobór bibliotek i uzasadnienie

| Potrzeba | Rozwiązanie | Uzasadnienie |
| -------- | ----------- | ------------ |
| Backend i model danych | **Elixir/OTP** | 
    procesy i transakcje bazy dobrze pasują do serwera przyjmującego zapisy; `:crypto` z OTP (Open Telecom Platform) 
    zawiera Ed25519, więc kryptografia nie wymaga zewnętrznej biblioteki. |
| Framework frontendowy | **Phoenix** (bez LiveView) |
    dojrzały w środowisku Elixira, dobrze testowalny; 
    dopóki strony są tylko do odczytu wystarczy renderowanie po stronie serwera;
    bez JavaScriptu na głównych stronach mniejsza powierzchnia ataku i prosta Content Security Policy;
    pełny LiveView niepotrzebny, dopóki nie ma interakcji w przeglądarce (to może się zmienić) |
| Szablony | **HEEx** (Phoenix.Component) | 
    szablony sprawdzane przy kompilacji, automatyczne escapowanie treści użytkownika |
| Serwer | **Bandit** | 
    domyślny serwer w Phoenix >=1.8, czysty Elixir |
| Baza danych | **Ecto + SQLite** |
    jedna baza w pliku; schematy i changesety dają walidację i ograniczenia; migracje;
    rozważany był Postgres ale przy małej skali projektu SQLite jest znacznym uproszczeniem. |
| Parser JSON | **Jason** | 
    standard w ekosystemie Elixira |
| Kryptografia | **Ed25519 z OTP** |
    małe klucze i podpisy, szybka weryfikacja, brak zewnętrznej zależności |

Świadomie **nie** używamy: Tailwind/esbuild i innych narzędzi budowania zasobów 
(jeden ręcznie napisany plik CSS), ORM poza Ecto, systemu kolejek, pamięci podręcznej.

### Odpowiedniki obowiązkowego rdzenia frameworka frontendowego

Tabela odnosi się do wszystkich siedmiu obszarów "Obowiązkowego rdzenia rozwiązania" z zasad projektu (s. 18), 
z uwzględnieniem minimum REST (s. 19) i zasad bibliotek/UI (s. 20). 
Nazwy mechanizmów Angulara i Reacta są przykładami, 
nie wymogiem użycia tych samych interfejsów programistycznych.

| Obszar | Typowy Angular / React | Implementacja i zakres w projekcie |
| ------ | ---------------------- | ---------------------------------- |
| Framework + TS | Aktualny Angular/React/Vue z TypeScriptem | 
    Phoenix 1.8 i LiveView 1.2. `assets/catalog.ts` typuje hook, a `assets/js/**/*.ts` 
    zawiera wszystkie własne źródła skryptów przeglądarki. 
    `tsc` sprawdza oba obszary.
    Zewnętrzna implementacja Ed25519 i wygenerowane pliki dla przeglądarki pozostają JS. 
    `tsc` przechodzi z pełnym `strict`, a `models.ts` oraz `studio-state.ts` typują projekcje i stan. 
    Dynamiczny adapter DOM w `ui.ts` i podpisywane treści zdarzeń nadal używają jawnych granic elastycznego JSON. |
| Architektura | Features, standalone/smart/dumb components, shared/core, pojedyncza odpowiedzialność | 
    `DiscoverLive` pobiera dane i zarządza stanem (smart), 
    `PageHTML.home` i `PublicComponents.project_card/file_card` prezentują wejściowe dane (dumb), 
    `Layouts` scala powłokę; funkcje HEEx mają `attr`/`slot`, `~H`, `:if`, `:for`. 
    Sekcje Studio są w `studio-{projects,resources,grants,profile,keys,read}.ts` z typowanymi zależnościami; 
    `studio.ts` nadal łączy nawigację, odczyt i zapis. |
| Routing | Angular/React Router, parametry, wejście bezpośrednie | 
    `Router` mapuje ścieżki, `DiscoverLive.handle_params/3` reaguje na `?view=` i 
    linki `patch`; `/i/:ref` i `/i/:ref/projects/:project_id` działają bezpośrednio; 
    Studio synchronizuje sekcję przez History API. |
| Formularze | Angular Forms / kontrolowane formularze, walidatory i błędy | 
    `/join` i Pracownia budują formularze w modułach UI, sprawdzają wymagane pola i formaty, 
    pokazują lokalne oraz serwerowe błędy. Backend waliduje ostatecznie podpisane zdarzenie; 
    ukrycie przycisku nie nadaje uprawnień. |
| API (REST) | HttpClient/fetch i serwis dostępu do danych, typowane DTO gdy potrzebne | 
    `assets/js/lib/api.ts` izoluje `fetch`, timeouty, statusy i błędy; 
    `GET` czyta tożsamości/projekty, a `POST /api/events` zapisuje podpisane operacje tworzenia, zmiany i usunięcia. 
    Projekcja jest odświeżana po zapisie. Modele DTO są w `models.ts`; katalog, tożsamość, dostęp i historię sprawdza 
    dekoder kształtu przed renderowaniem. Pozostałe odpowiedzi mają typy TS bez pełnego dekodowania runtime. 
    CRUD nie jest wystawiony jako osobne `PATCH/DELETE` zasobu. |
| Stan | Rozdzielenie stanu lokalnego, współdzielonego i serwerowego; spójna aktualizacja | 
    Lokalne: skarbiec IndexedDB i szkice w pamięci; 
    wspólne w Pracowni: `state` koordynatora i moduły sekcji; 
    serwerowe: projekcja `Directory`/API. `mount/3` i `assign/3` trzymają ulotny układ LiveView, 
    `phx-click` / `handle_event/3` obsługują zmianę. 
    Podpisane zapisy prowadzą do odczytu świeżego stanu; utracony wynik jest uzgadniany po ID zdarzenia. |
| UI | Komponenty wspólne, semantyka i spójne statusy | 
    Wspólny `app.css`, `Layouts`, `PublicComponents`, `assets/js/lib/ui.ts`; 
    etykiety i stany puste, `aria-current`, `aria-pressed`, tekstowe statusy oraz fokus. 
    Typowany hook `CatalogFocus` używa `mounted/updated/destroyed` i `AbortController`, 
    co odpowiada efektowi i cleanupowi komponentu. Pełny audyt czytnikiem ekranu nie był wykonywany. |

TypeScript obejmuje cykl życia hooka LiveView, operacje DOM, stan skarbca i publikacji, bajty oraz podpisy. 
`tsconfig.json` używa pełnego `strict`, w tym `noImplicitAny`, `strictNullChecks` i nieznanych wyjątków. 
`failure.ts` normalizuje błędy przeglądarki, `models.ts` sprawdza kluczowe projekcje odczytu, 
a sekcje formularzy przekazują jawnie typowane zależności. 
Wspólny konstruktor DOM jest dynamicznym adapterem z jawnymi `any`; 
część odpowiedzi API ma typy bez walidatora runtime. 

Nie stosujemy Chart.js, ponieważ w obecnym katalogu wykres nie wnosi danych potrzebnych użytkownikowi; 
podana przez prowadzącą biblioteka była przykładem scenariusza. 
`phoenix`/`phoenix_live_view` z npm to realna integracja hooka. 

Po `npm ci` uruchom `npm run typecheck`, `npm run lint` i `npm run build`. 
Build transpiluje `assets/js/**/*.ts` do tych samych ścieżek w `priv/static/assets/js`, 
po czym bundluje `assets/catalog.ts` do `live/catalog.js`. 
Wynik JS jest dołączony do wydania, więc uruchomienie serwera po `mix setup` nie wymaga npm. 
Plik deklaracji `assets/js/vendor/noble-ed25519.d.ts` opisuje API dostarczanej osobno biblioteki; 
źródło biblioteki pozostaje w `priv/static/assets/js/vendor/`.

## Struktura projektu

```
oktavarium/
  assets/                   TypeScript
  config/                   config.exs (wspólne), dev/test/prod.exs, runtime.exs (środowisko)
  lib/
    oktavarium.ex           opis warstw
    oktavarium/             DOMENA (bez zależności od Phoenixa)
      log.ex, log/          przyjmowanie i sprawdzanie podpisanych operacji
      blobs.ex, blobs/, resources.ex, resources/, projects.ex, repo.ex, content.ex
                            zasoby danych, projekty i multimedia
      authz.ex, access.ex, invites.ex, invites/, keys/, sessions.ex
                            klucze, sesja przeglądarki i autoryzacja
      cli.ex, cli/          narzędzia CLI dla API
      replay.ex             weryfikacja i odbudowa stanu z dzienników
      capability.ex, delegation.ex, grants/
                            zakresy uprawnień i łańcuchy grantów
    oktavarium_web/         WARSTWA WEBOWA
      auth.ex, endpoint.ex, router.ex, site_plug.ex
      controllers/          kontrolery i widoki (page_*, identity_*, event_controller, error_*, layouts)
      components.ex, public_components.ex
                            współdzielone komponenty (skracanie identyfikatorów, czas, odmiana liczebników, komponent klucza)
      api_error.ex, error_json.ex, not_found_error.ex
      mapowanie błędów domeny na JSON i status HTTP
    oktavarium_web.ex       wspólne `use` dla kontrolerów i widoków
    mix/oktavarium.ex       wspólny start repozytorium dla zadań operatora
    mix/tasks/              oktavarium.key.gen|key.show|identity.create|grant|profile|
                            event.verify|submit|ingest|rebuild
  priv/
    repo/migrations/        migracje bazy danych: identities, keys, events, grants, delegable
    static/                 assets/app.css, assets/js/*, favicon.svg, robots.txt
  test/
    oktavarium/, oktavarium_web/, mix/  testy odpowiadające strukturze lib/
    e2e/                    testy end-to-end w Pythonie dla przeglądarki
    js/                     testy JavaScript `node --test test/js/*_test.mjs`
    support/                DataCase, ConnCase, Fixtures
  docs/                     dokumentacja zgodnie z założeniami zajęć projektowych
```

Odpowiedniki podziału spotykanego we frontendzie:
**`shared/components`** to `oktavarium_web/components.ex` i `layouts.ex`;
**`features`** to funkcjonalności (katalog i strona tożsamości w `oktavarium_web/controllers`, 
zapis zdarzeń w `event_controller`);
**`pages`** to widoki HEEx (`page_html.ex`, `identity_html.ex`);
**`core/services`** to `lib/oktavarium` (domena).

## Stan, komunikacja i przepływ danych

### Odczyt

Użytkownik otwiera stronę -> kontroler pobiera aktualne dane z SQLite -> Phoenix renderuje HTML. 
Przy odczycie z Pracowni JavaScript pobiera dane przez publiczne API.

**`unlisted` działa tak samo jak `public` przy odczycie po adresie.** 
Różnica polega tylko na tym, że nie jest uwzględniane w publicznych katalogach.

### Zapis zwykłej zmiany

Przykład: zmiana opisu profilu.

1. Przeglądarka zbiera tekst i pokazuje podsumowanie.
2. Użytkownik zatwierdza zmianę i wybiera odpowiedni klucz sygnowania.
3. Klient buduje zdarzenie z kolejnym numerem `seq` i wskazaniem `prev`.
4. Podpisana koperta trafia do `POST /api/events`.
5. Serwer sprawdza podpis, łańcuch, uprawnienia i dane operacji.
6. Zdarzenie i wynikowa projekcja są zapisywane w jednej transakcji.

Nie można zmienić starego zdarzenia. 
Aktualizacja oznacza dopisanie nowego.

### Publikowanie pliku

W przypadku obrazu lub nagrania dochodzi osobny etap. 
Po potwierdzeniu zamiaru klient uzyskuje w razie potrzeby sesję kluczem autoryzacji i przesyła bajty do `POST /api/blobs`.
Serwer wylicza SHA-256 i zapisuje plik. Następnie klient podpisuje `resource.put`, 
które wskazuje hash, rozmiar, typ i miejsce pliku.

**Upload nie oznacza jeszcze publikacji.** 
Dopiero zaakceptowane zdarzenie przypisuje plik do tożsamości lub projektu.

## Model danych

### Tożsamości i klucze

Tożsamość powstaje ze zdarzenia `identity.genesis`. 
Jego ID staje się stałym ID tożsamości. 
Typy to **`person`** i **`collective`**. 
Uchwyt jest opcjonalny; nazwa wyświetlana znajduje się w profilu i może się zmieniać bez zmiany ID.

Rozdzielamy:

- **klucze sygnowania**, które podpisują zdarzenia;
- **klucze autoryzacji**, które pozwalają ustanowić sesję potrzebną np. do przesyłania bajtów;
- **skarbce lokalne**, przechowywane w przeglądarce, a nie w bazie serwera.

Klucz założycielski zachowuje pełne prawo do własnej tożsamości, również do funkcji dodanych później. Nie trzeba dopisywać mu nowych grantów.

### Projekty i zasoby

**Projekt to kontener zasobów należący do jednej tożsamości**, nie osobna tożsamość. 
Jego ID powstaje przy `project.create`. Zmiana nazwy albo slugu nie zmienia ID.

Zasób ma ID, typ, ścieżkę, opcjonalny `project_id`, hash pliku i metadane. 
Obecne rodzaje to `image`, `audio` i `site`; projekt jest osobną pozycją typu `project` w tabeli zasobów.

Przykładowe ścieżki wewnątrz projektu:

```text
images/plakat.png
audio/peron.ogg
site/index.html
site/css/style.css
```

Plik w przestrzeni głównej nie ma `project_id`. 
Zdjęcie profilowe jest obrazem pod `images/avatar` w tej właśnie przestrzeni. 
Aktualizacja istniejącego zasobu może zachować jego ID nawet po przeniesieniu do innego projektu.

### Granty i delegowanie

Grant określa **klucz odbiorcy, akcję, zasób i ewentualne ograniczenie czasu**. 
Może też pozwalać na dalsze delegowanie (`delegable`).

Dla projektu zakres opiera się na **ID projektu**, np.:

```text
<ID_TOZSAMOSCI>/projects/<ID_PROJEKTU>/images/*
```

Dzięki temu zmiana nazwy projektu nie przenosi uprawnień na przypadkowo inny projekt o takim samym slugu. 
Przeniesienie zasobu wymaga prawa usuwania w źródle i publikowania w celu.

Grant potomny nie może dawać więcej niż grant nadrzędny. 
Gdy rodzic wygaśnie lub zostanie cofnięty, potomek przestaje działać. 
Nie oznacza to usunięcia plików, które zostały wcześniej legalnie opublikowane.

### Dzienniki i koperty

Każda tożsamość ma **liniowy dziennik podpisanych zdarzeń**. 
Zdarzenie zawiera m.in.:

- `seq` — kolejny numer;
- `prev` — ID poprzedniego zdarzenia;
- `signer` — identyfikator klucza podpisującego;
- `type` i `body` — rodzaj i dane operacji;
- `ts` — czas zapisany przez klienta.

Obecny format to **koperta v2**. 
W tekście profilu oraz w metadanych projekty i zasoby przechowują w podpisanym 
ładunku **referencje SHA-256**, zamiast całą historyczną treść. 
Tekst może być dostarczony jako załącznik podczas zapisu; 
później jest przechowywany poza niezmiennym dziennikiem.

To ważny kompromis: **podpisana historia pozostaje**, 
ale niepotrzebne bajty treści można usunąć z magazynu bez zmiany podpisanych zdarzeń. 
Taki usunięty tekst lub plik nie będzie już możliwy do wyświetlenia; dziennik nadal przechowuje jego skrót.

Dla plików obowiązuje SHA-256 zapisany jako 64 znaki szesnastkowe. 
ID kluczy, zdarzeń i zasobów mają własną reprezentację base64url. 
Nie należy mylić skróconego tekstu widocznego na stronie z pełnym identyfikatorem.

### Odbudowa projekcji

Tabele z aktualnym profilem, grantami, kluczami, projektami i zasobami są **projekcją** zdarzeń, czyli wygodnym bieżącym widokiem. `Oktavarium.Replay` może odtworzyć je na podstawie podpisanego dziennika.

```sh
mix oktavarium.rebuild           # porównanie, bez zatwierdzania zmian
mix oktavarium.rebuild --apply   # zastosowanie odbudowanego stanu
```

Podczas odtwarzania sprawdzane są podpisy, kolejność i reguły. Historyczne uprawnienia ocenia się na podstawie czasu przyjęcia zdarzenia, tak aby późniejsze wygaśnięcie grantu nie unieważniało legalnej historii. Odbudowa wymaga zachowanych zdarzeń; nie przywróci utraconych bajtów plików.

## Własne strony HTML/CSS/JS

Pliki pod `site/` mogą tworzyć niezależną witrynę tożsamości lub projektu. Jeśli instancja ma ustawione `OKTAVARIUM_SITES_DOMAIN`, `SitePlug` podaje te pliki z **osobnego hosta**. Dla projektów adres jest wyprowadzany ze stabilnego ID, a nie ze slugu.

Oddzielny host i nagłówki bezpieczeństwa ograniczają dostęp kodu autora do głównej aplikacji, sesji i lokalnego skarbca. Nie traktujemy wgrywanego HTML jako zaufanego kodu Pracowni.

## Model danych

### Pojęcia

**Tożsamość** (`Oktavarium.Identities.Identity`):
publiczna przestrzeń z profilem i możliwością wyszukania. 
Jeden typ opisuje użytkownika, bota, organizację i projekt. 
Cechy takie jak strona główna, zasoby multimediów czy repozytorium git to moduły, 
które można włączyć dowolnej tożsamości. 
Tożsamość może mieć rodzica (`parent_id`), np. bot podporządkowany projektowi.

**Klucz sygnowania** (`Keys.IdentitySigningKey`):
właściwa kryptograficzna tożsamość. 
Podpisuje zdarzenia i granty. 
Zawsze należy do dokładnie jednej tożsamości (może to być tożsamość o ograniczonym profilu). 
Jedna tożsamość może mieć wiele kluczy sygnowania, różniących się uprawnieniami i ważnością.

**Klucz autoryzacji** (`Keys.IdentityAuthKey`): 
klucz logowania, np. passkey na jednym urządzeniu. 
Podpisuje wyzwanie logowania (domena `:login`) i współpodpisuje operacje wrażliwe: 
rotację kluczy sygnowania, odzyskiwanie konta, usunięcie konta. 
Relacja z tożsamościami to wiele-do-wielu;
każda tożsamość potrzebuje co najmniej jednego aktywnego klucza autoryzacji.

**Grant** (`Grants.Grant`): 
podpisane zdanie "klucz A pozwala kluczowi B na `action` na `resource` w oknie czasowym W". 
To **jedyny** mechanizm uprawnień:

* absolutne uprawnienia klucza założycielskiego to grant `"*"` na `"<id>/*"` (`Oktavarium.Delegation.root/1`);
* rola „utrzymuje projekt", „zarządza tłumaczeniem PL", „bot wrzuca jeden plik" to granty o węższej akcji i zasobie;
* zaproszenie na platformę to grant `identity.create` wystawiony przez klucz platformy (planowane).

Delegowanie podlega zasadzie **attenuation**: 
grant wystawiony na podstawie innego może być tylko równy lub węższy, 
zarówno co do capability (`Oktavarium.Capability.covers?/2`), jak i okna czasowego.

### Dzienniki

Najbliższy model to system kontroli wersji, w którym zmiany stanu są sterowane kryptograficznie:

| System kontroli wersji | Oktavarium |
| ---------------------- | ---------- |
| repozytorium | tożsamość (użytkownik, organizacja, projekt, cokolwiek) |
| historia commitów | **dziennik tożsamości**: łańcuch podpisanych zdarzeń |
| commit, jego rodzic | zdarzenie, `prev` (skrót poprzedniego zdarzenia) |
| autor i prawo zapisu | klucz sygnowania i granty |
| katalog roboczy | projekcja: tabele `identities`, `keys`, `grants`, strony profili |

* **Każda tożsamość ma własny dziennik.** 
    Nie ma globalnej kolejności zdarzeń ani globalnego `seq`. 
    Tabela `events` jest wspólna tylko fizycznie; 
    unikalny indeks `(identity_id, seq)` pilnuje liniowości każdego dziennika osobno.
* **Źródłem prawdy jest dziennik, a nie tabele.** 
    Stan i frontend są projekcją. `Oktavarium.Log.verify/1` sprawdza dziennik jednej 
    tożsamości wyłącznie na podstawie zapisanych bajtów (podpisy, identyfikatory, ciągłość), 
    więc wykrywa ręczne zmiany w bazie, a `Oktavarium.Log.envelopes/1` oddaje dziennik 
    w postaci, którą można przekazać dalej.
* To nie jest git i nie ma nim być. 
    Jeśli projekt będzie kiedyś potrzebował gita dla jednego lub wielu repozytoriów, to rozszerzenie: 
    repozytorium git jest wtedy zasobem projektu (`<id>/repo/...`), a dziennik projektu zapisuje, 
    kto ma prawo do niego pisać, i ewentualnie wskazania na stan repozytorium.
* Jedyna zależność między dziennikami to odwołania po identyfikatorze klucza:
    grant w dzienniku A wskazuje klucz, którego dom jest w dzienniku B. 
    Serwer wymaga dziś, żeby ten klucz był już u niego zarejestrowany (sprawdzenie stanu).
    Przy replikacji między instancjami (federacja) trzeba będzie to uściślić, 
    np. wskazując w grancie zdarzenie genesis klucza podmiotu.

### Log podpisanych zdarzeń

Stan w bazie jest **projekcją** dzienników podpisanych zdarzeń (`Oktavarium.Envelope`).

* Koperta niesie surowe bajty ładunku (JSON) dokładnie tak, jak je podpisano.
    Serwer nigdy ich nie serializuje ponownie, więc nie ma problemu kanonikalizacji.
* Podpis obejmuje prefiks domeny (`oktavarium/event/v1\0`), więc podpis z jednej
    domeny (np. logowania) nie przejdzie w innej.
* Ładunek zawiera klucz podpisujący. Id zdarzenia (skrót ładunku) zależy więc od klucza: 
    nie da się przejąć cudzego id tożsamości, powtarzając treść genesis własnym kluczem.
* Zdarzenie **genesis** ma `identity = nil`, `seq = 0`, `prev = nil`; 
    jego skrót jest identyfikatorem tożsamości. 
    Id nie zależy od serwera, co zostawia otwartą drogę do federacji.
* Kolejne zdarzenia mają `seq >= 1` i `prev` wskazujące poprzednie zdarzenie tej tożsamości. 
    Unikalny indeks `(identity_id, seq)` blokuje rozwidlenia, a `prev` powtórzenia.

#### Odbudowa projekcji dziennika

Skoro tabele `identities`, `keys`, `identity_auth_keys` i `grants` są funkcją
dzienników, można je odtworzyć: `mix oktavarium.rebuild` (`Oktavarium.Replay`).

* Dziennik jest czytany z samych bajtów w `events`; 
    klucz podpisującego wynika z jego id, więc uszkodzona projekcja nie przeszkadza. 
    Każde zdarzenie przechodzi weryfikację podpisu, `id`, tożsamości i `seq`.
* Zdarzenia przechodzą przez ten sam planner co przy przyjęciu, więc nie ma drugiej kopii reguł. 
    Uprawnienia ocenia się względem czasu przyjęcia zdarzenia (`inserted_at`), nie względem "teraz", 
    inaczej wygasłe granty unieważniałyby historię.
* Zdarzenie zależne od innego dziennika (delegat jeszcze nieznany) jest odkładane na kolejny przebieg. 
    Gdy przebieg nic nie zastosuje, odbudowa kończy się błędem i baza zostaje bez zmian. Całość to jedna transakcja.
* Domyślnie tylko sprawdza i raportuje rozbieżności (tabela: brakuje / nadmiarowe / zmienione); 
    `--apply` zatwierdza odbudowę, ale tylko gdy projekcja się rozjechała.
* Ręczne zmiany w projekcji (np. `visibility`) są rozbieżnością: czego nie ma w dziennikach, 
    tego nie ma po odbudowie. Przy przejściu na Postgresa wystarczy przenieść `events` i odbudować projekcję.

### Typy zdarzeń

Na razie istnieją trzy typy: CLI (`Oktavarium.CLI`) je tworzy, a `Oktavarium.Log.Planner`
przyjmuje. Ładunek (`body`) jest podpisany razem z resztą koperty.

| Typ | `body` |
| --- | ------ |
| `identity.genesis` | `kind` (`user`/`org`/`project`/`repo`), opcjonalnie `handle` i `auth_keys` (lista id kluczy autoryzacji) |
| `grant.create` | `subject` (id klucza), `action`, `resource`, opcjonalnie `not_before` i `expires_at` (sekundy unixowe), `delegable` (czy podmiot może przekazywać dalej, domyślnie nie) oraz `parent_grant` (id grantu, na podstawie którego wystawia klucz inny niż założycielski) |
| `profile.update` | `fields`: mapa `pole => tekst`, gdzie `null` usuwa pole. Pola: `display_name`, `bio`, `location`, `website` (zob. niżej) |

Zasób zaczyna się od id tożsamości (`<id>/lang/pl`), więc grant dotyczy zawsze
przestrzeni tożsamości, w której został wystawiony. CLI pilnuje tego lokalnie;
serwer musi sprawdzić to samo, bo nie może ufać klientowi.

Koperty żyją na razie jako pliki JSON (`payload`, `signer`, `signature`, wszystko w base64url). 
Kolejne zdarzenie tworzy się względem pliku poprzedniego, z którego CLI bierze tożsamość, `seq` i `prev`.

#### Profil

`profile.update` jest pierwszym typem zdarzenia, 
który korzysta z `Authz.permits?/6` zamiast z reguł wystawiania grantów. 
Każde zmieniane pole to osobny zasób `<id>/profile/<pole>`, a akcja to `profile.update`:

* klucz założycielski zmienia każde pole, bez grantów;
* delegat potrzebuje ważnego grantu (łańcuch do klucza założycielskiego, okno
    czasowe względem zegara serwera), który obejmuje **wszystkie** zmieniane pola:
    `<id>/profile/bio` daje tylko `bio`, `<id>/profile/*` cały profil. 
    Jedno niedozwolone pole odrzuca całe zdarzenie (`{:not_authorized, pole}`), 
    więc nie ma częściowych zapisów;
* zestaw pól jest zamknięty i ma limity długości (`Oktavarium.Identities.Profile`),
    bo profil jest publiczny; `website` to adres http(s), znaki sterujące są
    zabronione, pusty tekst jest błędem (pole usuwa się przez `null`).

Projekcją jest kolumna `identities.profile`. 
Planner liczy nowy, **cały** profil (zmiany scalone z profilem z faktów), 
a `Log` go zapisuje w tej samej transakcji co zdarzenie. 
Profil da się więc odtworzyć, odtwarzając dziennik zdarzenie po
zdarzeniu (zmiana po zmianie, kolejność ustala `seq`).

#### Reguły egzekwowane przez serwer

* **Genesis wymaga co najmniej jednego klucza autoryzacji** (`auth_keys`). 
    CLI tylko ostrzega, bo klient nie jest wiarygodny.
* **Jeden klucz sygnowania należy do dokładnie jednej tożsamości** (jego "domu").
    Ten sam klucz nie założy drugiej tożsamości, a klucz sygnowania nie może być
    kluczem autoryzacji (i odwrotnie). Klucz autoryzacji można współdzielić między tożsamościami.
* **Podmiot grantu musi być znanym kluczem sygnowania.** 
    Bot, któremu coś nadajemy, najpierw zakłada własną, ograniczoną tożsamość 
    (może korzystać z tego samego klucza autoryzacji), a potem dostaje grant.
* **Grant wystawia klucz założycielski albo delegat.** 
    Klucz założycielski nadaje dowolny grant i nie wskazuje grantu nadrzędnego 
    (jego władza jest absolutna). Każdy inny klucz musi wskazać `parent_grant`: 
    ważny grant `delegable`, którego jest podmiotem. Nowy grant musi być równy lub węższy: 
    capability objęta capability rodzica i okno czasowe w oknie rodzica 
    (`Oktavarium.Authz`, `Oktavarium.Delegation`). 
    Bez `delegable` podmiot może z uprawnienia tylko korzystać, nie przekazywać go.
* **Grant jest ważny, gdy ważny jest cały jego łańcuch** aż do klucza założycielskiego.
      Unieważnienie albo wygaśnięcie grantu w środku łańcucha odcina wszystko, co z niego
      wynikało (kaskadowo, przy sprawdzaniu, a nie przez przepisywanie potomków).
* **Ważność ocenia się względem czasu serwera**, a nie `ts` z koperty: `ts` podaje
    klient, więc nie może decydować o tym, czy grant jeszcze obowiązuje.
* Grant spoza danej tożsamości nie może być grantem nadrzędnym 
    (serwer widzi tylko granty z dziennika, do którego dopisuje zdarzenie).

### Warstwy weryfikacji

| Warstwa | Sprawdza |
| ------- | -------- |
| `Envelope.verify/1` | podpis, domena, struktura ładunku, zgodność klucza z deklarowanym, kształt genesis |
| `Log.Planner` (czyste funkcje) | reguły powyżej, `seq` i `prev` względem stanu, status kluczy, zajęty handle, powtórzone zdarzenia |
| `Log.append/1` | transakcja: ładowanie faktów, zapis zdarzenia i projekcji, wszystko albo nic |
| `Log.verify/1` | cały dziennik tożsamości od zera, tylko z zapisanych bajtów |
| `Authz` (czyste funkcje) | kto może wystawić grant, łańcuch grantów do klucza założycielskiego, attenuation, okna czasowe, unieważnienia; `permits?/6` dla zdarzeń, które wymagają uprawnienia (dziś `profile.update`) |

### Decyzje na MVP

* Klucze prywatne żyją w CLI (zadanie Mix), nie w przeglądarce.
* Bez trybu awaryjnego odzyskiwania przez administratora instancji; odzyskiwanie
    przez atestację wyznaczonych kluczy jest w modelu (grant), ale bez UI.
* SQLite jako baza (samohostowanie bez osobnego serwera).
    Zamiast migracji powstało narzędzie do odbudowy projekcji z dzienników 
    (`mix oktavarium.rebuild`), które ułatwi też późniejsze przejście do Postgresa jeśli potrzeba. 
    Zob. [04-api.md](04-api.md).
* Strony główne są tylko do odczytu, bez JavaScriptu i sesji; pisze się podpisanymi zdarzeniami przez API.
* Ed25519 z OTP (`:crypto`), JSON jako format ładunku.

## Ograniczenia

Powyższy model ma kilka problemów, 
przez które definitywnie nie można nazwać go "systemem kontroli wersji" jak w założeniach,
których jednak nie próbuje się rozwiązać w MVP projektu:

* Ładunek JSON z surowymi bajtami nie ma spójnego modelu, nie nadaje się na budowanie diffów ani drzew.
    Rozwiązaniem byłby własny kanoniczny format binarny, z adresowaniem obiektów treścią.
* Liniowy `seq`+`prev` i trzy typy zdarzeń nie tworzą naturalnego miejsca na diffy i forki tożsamości lub jej zasobów.
    Rozwiązaniem byłby model zdarzenia jako commit: rodzic + nowe drzewo stanu.
* Czas według zegara serwera jest bardzo mocnym uproszczeniem, w federacji nie ma jednego zegara,
    a `inserted_at` leży poza podpisem, więc replay *ufa* bazie. 
    Rozwiązaniem byłoby podpisanie potwierdzenia przyjęcia od instancji-gospodarza,
    co ograniczy zależność od zegara konkretnego serwera.
* `visibility: restricted` ukrywa tylko w HTML, co daje pozorną prywatność.
    Być może powinniśmy to usunąć i dać wszystko publiczne, albo należałoby używać operacji szyfrujących.
* Klucze w lokalnych plikach 0600 to też kompromis MVP, prawdziwe bezpieczeństwo kryptograficzne 
    mogą dać tylko szyfrowanie hasłem, klucze sprzętowe, passkeys, co *może* zostanie zaimplementowane i w tym prototypie.
* Prawdziwy model jak z systemu kontroli wersji 
    (drzewo Merkle'a, zdarzenia jako commity stanu, branche i diffy, skróty treści w commitach)
    wymaga znacznego nakładu pracy i skomplikowania modelu danych, co wykracza poza zakres tego prototypu.
