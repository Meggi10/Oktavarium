# 02. Wymagania

Dokument opisuje, 
**kto** korzysta z Oktavarium, 
**jakie procesy** przechodzi od początku do końca,
**co** system musi robić (wymagania funkcjonalne, MVP i dodatkowe)
oraz **kto co może** (role i uprawnienia).
Wymagania niefunkcjonalne są w [03-ux.md](03-ux.md), 
a interfejs HTTP w [04-api.md](04-api.md).

Każde wymaganie ma status względem aktualnego kodu:
**zrobione** (jest w repozytorium i pokryte testami, branch `main`) albo **planowane**.
Zakres MVP wynika z założeń projektu: 
platforma na zaproszenie, tożsamości jako klucze, uprawnienia jako podpisane granty, klucze prywatne w CLI
(zob. [05-architecture.md](05-architecture.md), "Decyzje na MVP").

## Role i uprawnienia

Uprawnienia nie wynikają z konta (email i hasła), tylko z **kluczy**.
Rola to sytuacja klucza względem tożsamości, a nie wartość w tabeli użytkowników.
Serwer nie zna pojęcia "zalogowany" w sesji: 
każde zdarzenie zapisujące jest podpisane, a serwer sprawdza, czy podpisujący klucz ma prawo do tej czynności.

| Rola | Kim jest | Skąd ma uprawnienia |
| ---- | -------- | ------------------- |
| **Gość** | Każdy, kto otworzy stronę lub wywoła API odczytu | brak kluczy; tylko odczyt publicznych danych |
| **Właściciel tożsamości** | posiadacz klucza założycielskiego (klucza, który podpisał zdarzenie genesis) | władza absolutna w przestrzeni własnej tożsamości (`<id>/*`) |
| **Delegat** | posiadacz klucza sygnowania, któremu nadano grant | wyłącznie to, co obejmuje jego grant, w oknie czasowym grantu |
| **Delegat z prawem przekazywania** | delegat, którego grant ma flagę `delegable` | j.w. oraz może nadać komuś równe lub węższe uprawnienia |
| **Operator instancji** | osoba z dostępem do serwera i bazy | konfiguracja instancji, wczytywanie kopert (`ingest`), sprawdzanie i odbudowa projekcji; **nie** ma uprawnień w cudzych tożsamościach (brak trybu awaryjnego) |
| **Klucz autoryzacji** (rola techniczna) | klucz logowania w sesji, np. passkey na urządzeniu | logowanie w przeglądarce i współpodpisywanie operacji wrażliwych |

Zasady, które egzekwuje serwer (szczegóły w [05-architecture.md](05-architecture.md)):

* jeden klucz sygnowania należy do dokładnie jednej tożsamości (jej "domu"),
* grant wystawia właściciel albo delegat z ważnyym grantem `delegable`, a nowy grant musi być równy lub węższy od nadrzędnego (zakres i czas),
* grant jest ważny, gdy ważny jest cały łańcuch do klucza założycielskiego,
* czas ważności ocenia się według zegara serwera, nie według czasu z koperty.

### Macierz uprawnień

`y` wolno, `n` nie wolno, `g` jeżli obejmuje to grant, `r` tylko gdy rejestracja otwarta, `?` planowane/do ustalenia.

| Czynność | Gość | Właściciel | Delegat | Operator |
| -------- | ---- | ---------- | ------- | -------- |
| Przeglądać katalog i strony tożsamości | `y` | `y` | `y` | `y` |
| Pobrać dziennik tożsamości (JSON) i go zweryfikować | `y` | `y` | `y` | `y` |
| Założyć tożsamość przez HTTP (genesis) | `r` | `r` | `r` | `y` (przez `ingest`) |
| Zmienić pole profilu tożsamości | `n` | `y` (każde pole) | `g` (`profile.update` na `<id>/profile/<pole>`) | `n` |
| Nadać grant w tożsamości | `n` | `y` (dowolny) | `g` (`delegable`) | `n` |
| Unieważnić grant | `n` | `y` | `n` | `?` |
| Zmienić uchwyt tożsamości | `n` | `y` | `n` | `?` |
| Dodać lub unieważnić klucz | `n` | `y` | `n` | `?` |
| Zaprosić nową osobę | `n` | `g` (od klucza platformy) | `?` | `?` |
| Przełączyć rejestrację otwartą/zamkniętą | `n` | `n` | `n` | `y` (konfiguracja) |
| Sprawdzić i odbudować projekcję bazy | `n` | `n` | `n` | `y` |

Zapis przez API jest dostępny dla każdego, kto potrafi podpisać zdarzenie.
Bez klucza z odpowiednim prawem serwer odrzuci zdarzenie (403), a podpis nie da się sfałszować.
"Gość" nie ma więc uprawnień zapisu, bo nie ma klucza.

## Główne procesy użytkownika (end-to-end)

Opis procesów, jakie system ma obsłużyć.
Polecenia w ramkach są prawdziwymi poleceniami CLI z repozytorium.

### P1. Założenie tożsamości (właściciel)

**Cel:** artystka Pelagia zakłada swoją tożsamość i pojawią się w katalogu.
**Warunki wstępne:** Pelagia ma CLI (projekt Elixir) lub dostęp do przeglądarki przy publicznej instancji; 
    serwer działa; rejestracja jest otwarta albo operator zgodził się wczytać jej zdarzenie.

1. Pelagia generuje klucz sygnowania i klucz autoryzacji (np. dla swojego laptopa).
    Klucze to pliki z uprawnieniami 0600, nigdy nie opuszczają jej komputera.
    `mix oktavarium.key.gen --out keys/pelagia-signing.key`
    `mix oktavarium.key.gen --kind auth --out keys/pelagia-laptop.key`
2. Odczytuje identyfikator klucza autoryzacji (`mix oktavarium.key.show`).
3. Podpisuje zdarzenie założycielskie (genesis) z rodzajem tożsamości, uchwytem i kluczem autoryzacji.
    Skrót tego zdarzenia staję się identyfikatorem tożsamości.
    `mix oktavarium.identity.create --key ... --kind user --handle pelagia --auth-key ID --out events/pelagia-0.json`
4. Wysyła zdarzenie na serwer: `mix oktavarium.submit events/pelagia-0.json`.
    Na instancji z zamkniętą rejestracją (domyślnie na produkcji) serwer odpowie `registration_closed`;
    wtedy operator wczytuje plik poleceniem `mix oktavarium.ingest events/pelagia-0.json`
    (to jest dzisiejsza realizacja "invite-only").
5. Tożsamość jest widoczna w katalogu (`/`) i pod adresem `/i/pelagia`.

**Wynik:** nowy dziennik z jednym zdarzeniem (`seg = 0`), strona tożsamości z oznaczeniem "Dziennik zweryfikowany".
**Ścieżki błędów:** zajęty uchwyt (`handle_taken`, 409); 
ten sam klucz sygnowania użyty drugi raz (`signing_key_already_registered`, 409); 
brak klucza autoryzacji (`auth_key_required`, 422);
zły podpis (`invalid_envelope`, 400).

### P2. Uzupełnienie profilu (właściciel)

**Cel:** Pelagia dodaje nazwę, opis, miejsce i stronę.

1. Podpisuje zmianę, wskazując plik poprzedniego zdarzenia (z niego CLI bierze identyfikator tożsamości, `seq` i `prev`):
    `mix oktavarium.profile --key keys/pelagia-signing.key --after events/viola-0.json --set display_name=Pelagia --set 'bio=zjadłam zupę.' --out events/pelagia-1.json`.
2. Wysyła: `mix oktavarium.submit events/pelagia-1.json`.
3. Strona `/i/pelagia` pokazuje nowy profil, a w dzienniku pojawia się zdarzenie `profile.update`. Pole można usunąć (`--unset location`).

**Wynik** zmieniony profil i nowe zdarzenie w historii.
**Ścieżki błędów:** niepoprawna wartość (np. `website` bez `http(s)://`, `invalid_body`, 422);
za długi tekst; zdarzenie nie jest następnym w dzienniku 
(`bad_seq`, 409 - trzeba pobrać głowę `GET /api/identifiers/ID/head` i podpisać ponownie).

### P3. Delegowanie uprawnień współpracowników lub botowi (właściciel -> delegat)

**Cel:** Pelagia pozwala pani Aleksandrze poprawiać wyłącznie opis (`bio`) jej tożsamości, do końca roku, bez oddawania mu swoich kluczy.

1. Pani Aleksandra zakłada własną tożsamość (P1) - serwer przyjmuje grant tylko dla znanego klucza sygnowania.
2. Pani Aleksandra przekazuje Pelagii identyfikator swojego klucza sygnowania.
3. Pelagia podpisuje grant: `profile.update` na `<id>/profile/bio`, ważny do 2026-12-31 23:59.
4. Wysyła grant na serwer. Na stronie `/i/pelagia` w sekcji "Uprawnienia" pojawia się wiersz z podmiotem, akcją, zasobem, oknem czasu i stanem.
5. Pani Aleksandra podpisuje zdarzenie `profile.update` ze zmianą `bio` w dzienniku Pelagii i wysyła je.
    Serwer akceptuje: łańcuch grantów jest ważny, pole objęte.
6. Gdy pani Aleksandra spróbuje zmienić `display_name`, serwer odrzuci całe zdarzenie
    (`not_authorized`, pole `display_name`). Po 2026-12-31 23:59 grant wygasa i przestaje działać.

**Wariant (przekazywanie dalej):** grant z flaga `delegable` pozwala pani Aleksandrze 
nadać Magdalenie węższe uprawnienie (`--parent-grant ID_GRANTU_PANI_ALEKSANDRY`);
próba nadania szerszego lub dłuższego jest odrzucana (`not_covered`, `window_exceeds_parent`).

### P4. Przeglądanie i weryfikacja (gość)

**Cel:** osoba z zewnątrz sprawdza, kto działa na instancji i czy historia jest uczciwa.

1. Otwiera katalog `/`: lista tożsamości z nazwą, uchwytem, początkiem opisu, rodzajem, liczbą zdarzeń i skrótem głowy dziennika.
2. Wchodzi na `/i/<uchwyt>` (albo `/i/<id>`): profil, dane identyfikacyjne, klucze publiczne, 
    tabela uprawnień i dziennik od najnowszych zdarzeń (strony "Starsze zdarzenia").
3. Czyta wskaźnik integralności: serwer sam weryfikuje dziennik i pokazuje wynik.
4. Pobiera dziennik jako JSON (`/api/identities/<id>/events`) i **sprawdza go niezależnie**
    (`mix oktavarium.event.verify`), nie ufając serwerowi.

**Wynik:** gość widzi aktualny stan i całą historię instancji, a podpisów nie musi brać na wiarę.

### P5. Utrzymanie instancji (operator)

**Cel:** operator stawia instancję, wpuszcza pierwszych użytkowników i dba o spójność.

1. Konfiguruje środowisko: `DATABASE_PATH`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`,
    opcjonalnie `OKTAVARIUM_REGISTRATION` (`open` / `closed`; na produkcji domyślnie `closed`).
2. Wczytuje zdarzenia założycielskie od zaproszonych osób: `mix oktavarium.ingest plik.json`
    (te same reguły co przez HTTP, ale bez ograniczenia rejestracji).
3. Okresowo sprawdza zgodność bazy z dziennikami: `mix oktavarium.rebuild`
    (kod wyjścia `!= 0` przy rozbieżności). Po awarii albo ręcznej edycji bazy naprawia ją `mix oktavarium.rebuild --apply`.
4. Wykonuje kopię zapasową pliku SQLite. Dziennik zdarzeń jest wystarczającym źródłem prawdy, więc projekcję zawsze można odtworzyć.

### P6. Zaproszenie nowej osoby (planowane)

Platforma jest z założenia zamknięta. Docelowo zaproszenie jest grantem `identity.create` wystawionym przez klucz platformy:
zaproszona osoba podpisuje genesis, a serwer akceptuje go dla zaproszenia z ograniczonym użyciem i czasem.
Do tego momentu rolę zaproszenia pełni operator (P1, krok 4).

### P7. Autoryzacja sesji i praca w przeglądarce (planowane)

Wyzwanie logowania podpisane kluczem autoryzacji (domena `oktavarium/login/v1`), sesja,
edycja profilu w przeglądarce. Dopóki klucze prywatne żyją w CLI, strony mogą być tylko do odczytu.
Chcemy jednak aby możliwa była edycja w przeglądarce, więc klucze prywatne powinny 
też móc istnieć w przeglądarce i być eksportowane do lub importowane z CLI.

## Wymagania funkcjonalne

Priorytet: 
**MVP** niezbędne do obsługi procesów P1-P5 i do obietnicy "zamknięta platforma z weryfikowalnymi uprawnieniami";
**Dodatkowe** rozszerzają platformę.

### Tożsamości i klucze

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| Generowanie kluczy Ed25519 (sygnowania i autoryzacji) do pliku z uprawnieniami 0600, bez nadpisywania istniejących plików | MVP | planowane |
| Założenie tożsamości zdarzeniem genesis: rodzaj (`user`, `org`, `project`), opcjonalny uchwyt (a-z, 0-9. `_`, `-`, 2-32 znaki), co najmniej jeden klucz autoryzacji | MVP | planowane |
| Identyfikator tożsamości to skrót zdarzenia genesis (niezależny od serwera) | MVP | planowane |
| Jeden klucz sygnowania należy do dokładnie jednej tożsamości; ten sam klucz nie może być jednocześnie kluczem sygnowania i autoryzacji | MVP | planowane |
| Unikalność uchwytów | MVP | planowane |
| Dodawanie i unieważnianie kluczy (rotacja, utrata urządzenia) | MVP | planowane |
| Zmiana uchwytu | Dodatkowe | planowane |
| Tożsamość podporządkowana (`parent`), np. bot w projekcie | Dodatkowe | planowane |

### Uprawnienia ("granty")

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| Nadanie uprawnienia: podmiot (znany klucz sygnowania), akcja, zasób, opcjonalne okno czasowe (`not_before`, `expires_at`) | MVP | planowane |
| Wzorce akcji i zasobów z symbolem `*`; zasób musi należeć do przestrzeni tożsamości, w której wystawiono grant | MVP | planowane |
| Właściciel nadaje dowolny grant; delegat tylko na podstawie własnego grantu `delegable` | MVP | planowane |
| Zawężanie (attenuation): pochodny grant nie może mieć szerszego zakresu ani dłuższego okna niż nadrzędny | MVP | planowane |
| Ważność grantu zależy od całego łańcucha do klucza założycielskiego; wygaśnięcie lub unieważnienie ogniwa odcina pochodne | MVP | planowane |
| Ważność oceniana według czasu serwera, nie czasu z koperty | MVP | planowane |
| Unieważnienie grantu zdarzeniem `grant.revoke` | MVP | planowane |
| Zaproszenia jako granty (`identity.create` od klucza platformy, z limitem użyć) | MVP | planowane |

### Dziennik zdarzeń

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| Każda tożsamość ma własny dziennik: zdarzenia numerowane `seq`, łańcuch `prev`, brak rozwidleń i powtórzeń | MVP | planowane |
| Zdarzenie jest podpisane (Ed25519, osobna domena podpisu), a serwer przechowuje surowe, podpisane bajty bez ponownej serializacji | MVP | planowane |
| Zapis atomowy: zdarzenie i jego projekcja zapisują się razem albo wcale | MVP | planowane |
| Weryfikacja dziennika od zera wyłącznie z zapisanych bajtów (`Log.verify`), także po stronie klienta (`mix oktavarium.event.verify`) | MVP | planowane |
| Odbudowa projekcji z dzienników: sprawdzanie rozbieżności i naprawa (`mix oktavarium.rebuild`) | MVP | planowane |
| Ponawianie zapisu po konflikcie `bad_seq` (pobranie głowy i ponowne podpisanie) | MVP | planowane |
| Współpodpisywanie operacji wrażliwych kluczem autoryzacji | Dodatkowe | planowane |
| Replikacja dzienników między instancjami (federacja) | Dodatkowe | planowane |

### Profil

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| Zdarzenie `profile.update` zmienia pola `display_name` (<= 80 znaków, jedna linia), `bio` (<= 2000, wiele linii), `location` (<= 80), `website` (<= 200 http/https); `null` usuwa pole | MVP | planowane |
| Każde pole to osobny zasób `<id>/profile/<field>`; właściciel zmienia wszystkie, delegat tylko te objęte grantem; jedno niedozwolone pole odrzuca całe zdarzenie | MVP | planowane |
| Walidacja: zamknięty zestaw pól, zakaz znaków sterujących, pusty tekst jest błędem | MVP | planowane |
| Awatar, linki do innych usług, dodatkowe pola | Dodatkowe | planowane |
| Zasoby (obrazy, audio, HTML/CSS/JS, repozytoria GIT) | Dodatkowe | planowane |

### Przeglądanie (strony publiczne)

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| Katalog tożsamości: nazwa, uchwyt, początek opisu, rodzaj, liczba zdarzeń, skrót głowy; stan pusty z instrukcją | MVP | planowane |
| Strona tożsamości pod uchwytem lub identyfikatorem; adres z identyfikatorem przekierowuje na adres z uchwytem | MVP | planowane |
| Na stronie: profil, dane identyfikacyjne, klucze publiczne, tabela uprawnień ze stanem (aktywny, unieważniony, wygasły, oczekujący, uszkodzony łańcuch), dziennik ze stronicowaniem | MVP | planowane |
| Wskaźnik integralności dziennika (serwer weryfikuje podpisy i łańcuch przy każdym wyświetleniu) oraz odnosnik do pobrania JSON | MVP | planowane |
| Wyszukiwanie tożsamości po nazwie, uchwycie, rodzaju | MVP | planowane |
| Strony projektów, zasobów, repozytoriów i moduły tożsamości (strona główna, pliki) | Dodatkowe | planowane |
| Tożsamości o widoczności `restricted` ukryte w katalogu (dziś ukrywane na stronach, ale nie w API) | Dodatkowe | planowane |

### API i narzędzia operatora

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| `POST /api/events` przyjmuje kopertę, odpowiada 201 albno ustruktyzowanym błędem JSON z właściwym statusem | MVP | planowane |
| `GET /api/identities/:id/head` i `GET /api/identities/:id/events?after=N` | MVP | planowane |
| Przełącznik rejestracji (`registration: :open / :closed`), na produkcji domyślnie zamknięta | MVP | planowane |
| `mix oktavarium.submit` (wysłanie kopert), `mix oktavarium.ingest` (wczytanie do bazy bez HTTP) | MVP | planowane |
| Ograniczanie liczby żądań do API | MVP | planowane |
| Szyfrowanie plików z kluczami prywatnymi hasłem | MVP | planowane |
| Wydanie produkcyjne (release), instrukcja kopii zapasowych | MVP | planowane |

### Przeglądarka

| Wymaganie | Priorytet | Status |
| --------- | --------- | ------ |
| Generowanie kluczy i podpisanie zdarzenia `genesis`, z użyciem ważnego zaproszenia (jeśli rejestracja zamknięta) w przeglądarce | MVP | planowane |
| Logowanie w przeglądarce wyzwaniem podpisanym kluczem autoryzacji (passkey) i sesja | MVP | planowane |
| Edycja profilu i zarządzanie uprawnieniami w przeglądarce | MVP | planowane |

## Poza zakresem MVP

* federacja (replikacja dzienników między instancjami);
* zasoby projektu: repozytoria git, obrazy, audio, HTML/CSS/JS;
* tryb awaryjnego odzyskiwania tożsamości przez administratora instancji 
    (odzyskiwanie ma iść przez atestację wyznaczonych kluczy, bez interfejsu);

## Powiązanie z kodem i testami

| Obszar | Moduły | Testy |
| ------ | ------ | ----- |
| Koperty i podpisy | `Oktavarium.Crypto`, `Oktavarium.Envelope` | `crypto_test`, `envelope_test` |
| Zakres uprawnień i delegowanie | `Oktavarium.Capability`, `Oktavarium.Delegation`, `Oktavarium.Authz` | `capability_test`, `delegation_test`, `authz_test` |
| Przyjmowanie zdarzeń | `Oktavarium.Log`, `Oktavarium.Log.Planner` | `log_test`, `log_planner_test` |
| Profil | `Oktavarium.Identities.Profile` | `identities_profile_test` |
| Odbudowa projekcji | `Oktavarium.Replay` | `replay_test`, `mix/tasks/oktavarium_rebuild_test` |
| CLI i zadania Mix | `Oktavarium.Cli`, `Mix.Tasks.Oktavarium.*` | `cli_test`, `oktavarium_tasks_test` |
| API i strony | `OktavariumWeb.*`, `Oktavarium.Directory` | `oktavarium_web/api_test`, `pages_test`, `components_test`, `directory_test` |
