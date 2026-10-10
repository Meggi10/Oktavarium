# 04. Zaplecze danych i API

## Wybór zaplecza danych

Oktavarium ma **własny, lokalny backend**:
aplikację Elixir/Phoenix z bazą SQLite w jednym pliku.
Nie korzysta z żadnego zewnętrznego, publicznego API ani z usługi typu "backend jako usługa".
Wszystkie zasoby opisane niżej wystawia sam projekt, co pozwala na zachowanie całkowitej lokalności instancji.

### Uzasadnienie

| Kryterium | Decyzja i powód |
| --------- | --------------- |
| Własny backend zamiast zewnętrznego API | Sens projektu to tożsamość i uprawnienia jako **podpisane zdarzenia**,
    których serwer nie może zmienić po cichu. Zewnętrzna usługa (np. gotowy BaaS albo dostawca logowania)
    zabrałaby to, co jest sednem modelu: własność danych i niezależność od dostawcy. 
    Dodatkowo platforma ma być **samohostowalna**, gdy ktoś sobie tego życzy. |
| Źródło prawdy | Dziennik podpisanych zdarzeń (tabela `events`, surowe bajty).
    Pozostałe tabele (`identities`, `keys`, `identity_auth_keys`, `grants`) 
    to projekcja, którą można odbudować (`mix oktavarium.rebuild`). |
| Baza: SQLite | jeden plik, zero osobnego serwera, proste kopie zapasowe - pasuje do małej, zakmniętej instancji.
    Zapisy do bazy są i tak serializowane (jeden zapis do dziennika naraz), więc brak współbieżnych zapisów
    nie jest tu istotną wadą. |
| Baza: Postgres rozważony i odłożony | Daje lepszą współbieżność i operacje na dużej skali, ale wymaga osobnego serwera.
    Przejście jest przygotowane: zmiana adaptera (`postgrex`), usunięcie `default_transaction_mode: :immediate`,
    jawna blokada na dziennik (`pg_advisory_xact_lock`) i odbudowa projekcji. Na potrzeby MVP wybrano SQLite. |
| Lokalny backend a "publiczne REST API" | Własne REST API jest publiczne w tym sensie, 
    że odczyt dzienników nie wymaga autoryzacji logowania, a zapis wymaga tylko podpisu kryptograficznego. |

### Co jest po stronie klienta

Strony HTML renderuje serwer (bez JavaScriptu).
Klient "piszący" to CLI w tym samym repozytorium (`mix oktavarium.*`), 
które podpisuje zdarzenia lokalnie i wysyła je przez `POST /api/events`.
Przeglądarka jest szczególnym rodzajem klienta, który korzysta z tego samego API, co narzędzie CLI.

## Zasoby

| Zasób | Opis | Identyfikacja |
| ----- | ---- | ------------- |
| Tożsamość | użytkownik / maszyna / organizacja / projekt | `id` (skrót zdarzenia genesis, base64url) albo `handle` |
| Zdarzenie | podpisana zmiana w dzienniku tożsamości | `id` (skrót ładunku), para `(identity, seq)` |
| Głowa dziennika | `seq` i `id` ostatniego zdarzenia; potrzebne do podpisania następnego | `id` tożsamości |
| Koperta | postać zdarzenia w sieci: `payload`, `signer`, `signature` (base64url) | -- |

Typy zdarzeń (pole `type` w ładunku):
`identity.genesis`, `grant.create`, `profile.update`.
Treść każdego opisuje [05-architecture.md](05-architecture.md), "Typy zdarzeń".

## Endpointy

Dwie grupy tras: strony dla ludzi (HTML) i API dla programów (JSON).

### API (JSON)

| Metoda | Ścieżka | Uwierzytelnienie | Opis |
| ------ | ------- | ---------------- | ---- |
| `POST` | `/api/events` | podpis w kopercie | dopisuje zdarzenie do dziennika; genesis zakłada tożsamość |
| `GET` | `/api/identities/:id/head` | brak (publiczne) | głowa dziennika: `seq` i `id` ostatniego zdarzenia |
| `GET` | `/api/identities/:id/events?after=N` | brak (publiczne) | koperty zdarzeń o `seq > N` (domyślnie wszystkie) |

Brak `PUT`, `PATCH` i `DELETE`:
zdarzeń się nie zmienia ani nie usuwa.
Zmiana stanu to zawsze **nowe** zdarzenie dopisane na końcu dziennika,
widoczna zmiana wynika z projekcji tego dziennika (jego prezentacja).

#### `POST /api/events`

Nagłówek `Content-Type: application/json`, ciało: koperta (taka sama jak plik JSON z CLI).

```json
{
  "payload":   "<ładunek zdarzenia w base64url>",
  "signer":    "<id klucza podpisującego>",
  "signature": "<podpis Ed25519 w base64url>"
}
```

Ładunek (po zdekodowaniu) to JSON z polami 
`v`, `signer`, `identity`, `seq`, `prev`, `type`, `body`, `ts`.
Serwer **nie serializuje go ponownie**: weryfikuje podpis dokładnie na przesłanych bajtach.

Odpowiedź `201 Created`:

```json
{ "id": "<id zdarzenia>", "identity": "<id tożsamości>", "seq": 1, "type": "profile.update" }
```

Dla genesis `identity` jest równe `id`, a `seq` to 0.

#### `GET /api/identities/:id/head`

```json
{ "identity": "<id>", "seq": 3, "id": "<id ostatniego zdarzenia>" }
```

Skąd piszący bierze `seq + 1` i `prev` następnego zdarzenia. 
`404`, gdy tożsamość nie istnieje.

#### `GET /api/identities/:id/events?after=N`

```json
{ "identity": "<id>", "head": 3, "events": [ { "payload": "...", "signer": "...", "signature": "..." } ] }
```

Koperty w kolejności `seq`, gotowe do niezależnej weryfikacji (`mix oktavarium.event.verify`) lub
replikacji. `after` musi być liczbą całkowitą ≥ 0, inaczej `422 invalid_body` (`field: "after"`).

### Strony (HTML)

| Metoda | Ścieżka | Opis |
| ------ | ------- | ---- |
| `GET` | `/` | katalog tożsamości |
| `GET` | `/i/:ref` | strona tożsamości; 
    `ref` to uchwyt albo id (id tożsamości z uchwytem przekierowuje na adres z uchwytem). Parametr `?before=N` stronicuje dziennik. |

Nieznana trasa lub tożsamość: `404` w HTML albo, przy `Accept: application/json`,
`{"error": {"code": "not_found"}}`. Metoda `HEAD` działa dla tras `GET`.

Do zrobienia: subdomeny tożsamości dla zasobów własnych frontendu (HTML/CSS/JS).

### Przykład użycia

```sh
# głowa dziennika
curl https://oktavarium.example.org/api/identities/ID/head

# wysłanie koperty (to samo robi `mix oktavarium.submit`)
curl -X POST https://oktavarium.example.org/api/events \
  -H 'Content-Type: application/json' \
  --data @events/pelagia-1.json
```

## Błędy

Błąd ma stały kształt, a `code` pochodzi z walidacji po stronie serwera:

```json
{ "error": { "code": "bad_seq", "expected_seq": 4 } }
```

| Status | Kody (`code`) | Znaczenie |
| ------ | ------------- | --------- |
| 400 | `invalid_envelope` | koperta nieczytelna lub zły podpis (`reason`) |
| 403 | `not_authorized` (z polem `field` dla profilu), 
    `unknown_signer`, `not_signing_key`, `key_revoked`, 
    `parent_not_delegable`, `grant_inactive`, `broken_chain`, `registration_closed` | 
    podpisujący nie ma prawa albo rejestracja jest zamknięta |
| 404 | `unknown_identity`, `not_found` | nie ma takiej tożsamości lub trasy |
| 409 | `duplicate_event`, `bad_seq` (z `expected_seq`), 
    `bad_prev`, `handle_taken`, `signing_key_already_registered`, `conflict` | 
    konflikt ze stanem dziennika; po `bad_seq` pobierz głowę i podpisz zdarzenie ponownie |
| 422 | `invalid_body` (z `field`), `not_covered`, `window_exceeds_parent`, 
    `invalid_window`, `unknown_subject_key`, `subject_not_signing_key`, `unsupported_type` i inne | 
    zdarzenie poprawnie podpisane, ale odrzucone przez reguły |

## Autoryzacja

**Nie ma haseł, tokenów ani sesji w API**.
Autoryzacja jest wbudowana w samo zdarzenie:

1. **Uwierzytelnienie = podpis.**
    Każde zapisujące żądanie niesie kopertę podpisaną kluczem Ed25519.
    Serwer sprawdza podpis (domena `oktavarium/event/v1`), więc wie, **który klucz** to wysłał,
    i nie da się go podrobić ani przekierować w inny kontekst.
2. **Autoryzacja = granty.**
    Klucz założycielski może wszystko w swojej tożsamości;
    każdy inny klucz musi mieć ważny łańcuch grantów do klucza założycielskiego, 
    obejmujący daną akcję i zasób w bieżącym czasie serwera (zob. [05-architecture.md](05-architecture.md)).
3. **Odczyt jest publiczny.**
    `GET` nie wymaga uwierzytelnienia: dzienniki są jawne i mają być weryfikowalne przez każdego.
4. **Rejestracja nowych tożsamości** jest bramkowana ustawieniem
    `config :oktavarium, registration:` (`:open` w dev/test, `:closed` na produkcji; 
    nadpisanie zmienną środowiskową `OKTAVARIUM_REGISTRATION`). 
    Przy `:closed` genesis przez HTTP kończy się `403 registration_closed`, 
    a operator wczytuje go poleceniem `mix oktavarium.`

## Ograniczenia wybranego rozwiązania

| Obszar | Ograniczenie | Skutek / plan |
| ------ | ------------ | ------------- |
| Limity zapytań | **brak** ograniczania liczby żądań | do czasu dodania (planowane) instancję należy chronić na poziomie serwera pośredniczącego; rejestracja jest na produkcji zamknięta |
| Rozmiar żądania | parser JSON przyjmuje do 64 KiB | wystarcza dla koperty (kilkaset bajtów) |
| Paginacja | `GET .../events` zwraca **wszystkie** zdarzenia po `after`, bez limitu | klient pobiera przyrostowo (`after=<ostatni seq>`); limit strony do dodania |
| Współbieżność zapisu | SQLite serializuje zapisy (`BEGIN IMMEDIATE`) | zapisy kolejkują się; dwóch piszących do jednego dziennika zderza się na `seq` i przegrany dostaje `409 bad_seq` - musi pobrać głowę i podpisać ponownie (ponawianie w CLI planowane) |
| Trwałość danych | dane w jednym pliku SQLite na dysku serwera | kopie zapasowe to obowiązek operatora; 
    dziennik jest źródłem prawdy, więc po uszkodzeniu projekcji wystarczy `mix oktavarium.rebuild --apply`, 
    ale utraty samego pliku to nie naprawia |
| Dostępność | jeden węzeł, brak replikacji i failoveru | awaria serwera = niedostępność; 
    brak SLA. Federacja (replikacja dzienników) jest poza zakresem MVP |
| Skalowanie | rozwiązanie dla małej, zamkniętej społeczności | przejście na Postgresa opisane wyżej |
| Wersjonowanie API | trasy bez numeru wersji; ładunek ma pole `v: 1` | zmiany niezgodne wstecz wymagają nowej wersji ładunku |
| Widoczność | pole `visibility: restricted` ukrywa tożsamość na stronach, ale **nie** w API | dane w API są publiczne; nie przechowuj w dzienniku niczego poufnego |
| Niezmienność | zdarzenia są jawne i nieusuwalne | nie wpisuj w profil danych, których nie chcesz publikować na zawsze |
| Zegar | ważność grantów liczona według zegara serwera | błędny zegar serwera = błędna ważność grantów |
| Przepływ lokalny | `mix oktavarium.ingest` i `mix oktavarium.rebuild` działają na bazie bezpośrednio | wymagają dostępu do maszyny z bazą; `rebuild` blokuje zapisy na czas transakcji |

Przy wdrożeniu produkcyjnym wymagane zmienne: `DATABASE_PATH` (ścieżka pliku SQLite),
`SECRET_KEY_BASE`; opcjonalne: `PHX_HOST`, `PORT`, `POOL_SIZE`, `OKTAVARIUM_REGISTRATION`.
