# 05. Architektura

Dokument opisuje architekturę aplikacji (stos, strukturę projektu, biblioteki, stan, komunikację)
oraz model danych tożsamości, uprawnień i dzienników zdarzeń.
Kod jest źródłem prawdy; ten plik tłumaczy, **dlaczego** jest tak, a nie inaczej.
Część od sekcji "Model domeny" w dół to rozwinięta wersja wcześniejszego dokumentu o modelu platformy.

## Przegląd

Oktavarium to jedna aplikacja Elixir (OTP) o trzech warstwach. Zależności idą tylko w dół.

```
  przeglądarka            CLI (mix oktavarium.*)        operator (mix oktavarium.ingest / rebuild)
       |  GET (HTML)           |  POST /api/events            |  bezpośrednio do bazy
       v                       v                              v
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
| Phoenix HTML, Phoenix LiveView | `~> 4.2` (4.3.0), `~> 1.1` (1.2.12) | szablony HEEx i komponenty funkcyjne; **gniazda LiveView nie są narazie używane** |
| Bandit | `~> 1.8` (1.12.5) | serwer HTTP |
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

## Struktura projektu

```
oktavarium/
  config/                   config.exs (wspólne), dev/test/prod.exs, runtime.exs (środowisko)
  lib/
    oktavarium.ex           opis warstw
    oktavarium/             DOMENA (bez zależności od Phoenixa)
      TODO
    oktavarium_web/         WARSTWA WEBOWA
      endpoint.ex, router.ex
      controllers/          kontrolery i widoki (page_*, identity_*, event_controller, error_*, layouts)
      components.ex         współdzielone komponenty (skracanie identyfikatorów, czas, odmiana liczebników, komponent klucza)
      api_error.ex          mapowanie błędów domeny na JSON i status HTTP
    oktavarium_web.ex       wspólne `use` dla kontrolerów i widoków
    mix/oktavarium.ex       wspólny start repozytorium dla zadań operatora
    mix/tasks/              oktavarium.key.gen|key.show|identity.create|grant|profile|
                            event.verify|submit|ingest|rebuild
  priv/
    repo/migrations/        identities, keys, events, grants, delegable
    static/                 assets/app.css, favicon.svg, robots.txt
  test/
    oktavarium/, oktavarium_web/, mix/  testy odpowiadające strukturze lib/
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

Na dzień dzisiejszy **stan po stronie klienta nie istnieje.**
Strony są renderowane na serwerze przy każdym żądaniu;
nie ma sesji, ciasteczek, formularzy ani skryptów;
Klient piszący trzyma tylko pliki kluczy i pliki kopert (`events/*.json`)
z których bierze `seq` i `prev` kolejnego zdarzenia.

**Stan po stronie serwera** ma jedno źródło prawdy:

* `events` - podpisane zdarzenia (surowe bajty); **niezmienne**, tylko dopisywane;
* tabele projekcji (`identifiers`, `keys`, `identity_auth_keys`, `grants`) - 
    wyliczone ze zdarzeń w tej samej transakcji, w której zdarzenie zapisano; da się je odtworzyć z dzienników.

**Komunikacja:**

* klient -> serwer: `GET .../head` po `seq` i `prev`; `POST /api/events` z kopertą;
* operator -> baza: `mix oktavarium.ingest`, `mix oktavarium.rebuild` bez HTTP;
* serwer -> serwer (federacja): poza MVP; dziennik pobierany przez `GET .../events` już w postaci gotowej do replikacji. 

**Przepływ zapisu zdarzenia:**

```
CLI podpisuje kopertę --POST--> Router --> EventController
                                              |  (parsowanie, bramka rejestracji)
                                              v
                                   Log.append(koperta)  [jedna transakcja BEGIN IMMEDIATE]
                                     1. Envelope.verify  (podpis, struktura)
                                     2. load_facts       (stan z bazy: głowa, grant, klucze)
                                     3. Planner.plan     (czysta decyzja + lista operacji)
                                        |> Authz         (uprawnienia, łańcuch grantów)
                                     4. zapis: zdarzenie + projekcja
                                              |
                       201 {id, identity, seq, type}  albo  błąd {error:{code,…}} + status
```

**Obsługa błędów:** 
domena zwraca krotki `{:ok, …}` / `{:error, powód}`; `OktavariumWeb.ApiError`
zamienia powód na kod i status HTTP; strony używają `ErrorHTML`. Błędy zapisu nie zostawiają
niczego w bazie (transakcja).

**Współbieżność:** 
zapisy do bazy serializuje `BEGIN IMMEDIATE`; unikalny indeks
`(identity_id, seq)` jest drugim zabezpieczeniem przed rozwidleniem dziennika.

**Testowanie:** 
rdzeń i planner bez bazy (czyste funkcje), `Log`, `Replay`, `Directory` na
prawdziwej bazie SQLite z piaskownicą Ecto, API i strony przez `Phoenix.ConnTest`, 
zadania Mix z podmienioną powłoką. 

## Model danych

### Pojęcia

**Tożsamość** (`Oktavarium.Identities.Identity`):
publiczna przestrzeń z profilem i możliwością wyszukania. 
Jeden typ opisuje użytkownika, bota, organizację i projekt. 
Cechy takie jak strona główna, zasoby multimediów czy repozytorium git to moduły, 
które można włączyć dowolnej tożsamości. 
Tożsamość może mieć rodzica (`parent_id`), np. bot podporządkowany projektowi.

**Klucz sygnowania** (`Keys.Key`, `kind: :signing`):
właściwa kryptograficzna tożsamość. 
Podpisuje zdarzenia i granty. 
Zawsze należy do dokładnie jednej tożsamości (może to być tożsamość o ograniczonym profilu). 
Jedna tożsamość może mieć wiele kluczy sygnowania, różniących się uprawnieniami i ważnością.

**Klucz autoryzacji** (`Keys.Key`, `kind: :auth`): 
klucz logowania, np. passkey na jednym urządzeniu. 
Podpisuje wyzwanie logowania (domena `:login`) i współpodpisuje operacje wrażliwe: 
rotację kluczy sygnowania, odzyskiwanie konta, usunięcie konta. 
Relacja z tożsamościami to wiele-do-wielu (`Keys.IdentityAuthKey`); 
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
* **Jeden klucz sygnowania należy do dokładnie jednej tożsamości** (jego „domu").
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
* Treści profilu na zawsze w dzienniku oznacza, że operator instancji nie może usunąć nielegalnej treści.
    Rozwiązaniem powinno być to by dziennik commitował do skrótów, wtedy treść można usunąć bez zerwania łańcucha.
* Klucze w lokalnych plikach 0600 to też kompromis MVP, prawdziwe bezpieczeństwo kryptograficzne 
    mogą dać tylko szyfrowanie hasłem, klucze sprzętowe, passkeys, co *może* zostanie zaimplementowane i w tym prototypie.
* Prawdziwy model jak z systemu kontroli wersji 
    (drzewo Merkle'a, zdarzenia jako commity stanu, branche i diffy, skróty treści w commitach)
    wymaga znacznego nakładu pracy i skomplikowania modelu danych, co wykracza poza zakres tego prototypu.
