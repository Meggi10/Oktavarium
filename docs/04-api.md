# 04. Zaplecze danych i API

## Wybór zaplecza danych

Oktavarium ma własny backend w **Elixirze i Phoenix**. 
Dane tabelaryczne trzyma w **SQLite**, a większe pliki w lokalnym magazynie blobów. 
Nie korzysta z zewnętrznego systemu logowania ani gotowej usługi typu backend-as-a-service.
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

Strony HTML renderuje serwer, JavaScript jest używany dla funkcji autoryzacji sesji, podpisywania i edycji.
Klient "piszący" to CLI w tym samym repozytorium (`mix oktavarium.*`),
albo autoryzowana sesja w przeglądarce, 
który podpisuje zdarzenia lokalnie i wysyła je przez `POST /api/events`.
Przeglądarka jest szczególnym rodzajem klienta, który korzysta z tego samego API, co narzędzie CLI, 
którego klucze autoryzacji i sygnowania trzymane są zaszyfrowane i lokalnie.

## Zasoby

| Zasób | Co oznacza |
| ----- | ---------- |
| **Tożsamość** | Osoba albo kolektyw. Ma stałe ID, opcjonalny uchwyt, profil i własny dziennik. |
| **Projekt** | Kontener zasobów należący do tożsamości. Ma stabilne ID i zmienialny slug. |
| **Zasób** | Obraz, nagranie lub plik strony; ma ID, ścieżkę, hash i metadane. |
| **Blob** | Bajty pliku opisane skrótem SHA-256. |
| **Zdarzenie** | Podpisana operacja zmieniająca stan. |
| **Grant** | Zapis mówiący, który klucz może wykonać jaką czynność i gdzie. |

Typy zdarzeń (pole `type` w ładunku):
`identity.genesis`, `grant.create`, `profile.update`.
Treść każdego opisuje [05-architecture.md](05-architecture.md), "Typy zdarzeń".

## Endpointy

### Publiczne strony HTML

| Metoda | Ścieżka | Opis |
| --- | --- | --- |
| `GET` | `/` | Odkrywaj. Filtry przez `?view=images`, `audio`, `projects`, `people`. |
| `GET` | `/i/:ref` | Profil osoby lub kolektywu po uchwycie albo ID. |
| `GET` | `/i/:ref/projects/:project_id` | Publiczny widok projektu. |
| `GET` | `/join` | Formularz tworzenia tożsamości. |
| `GET` | `/login` | Odblokowanie i przywracanie skarbca. |
| `GET` | `/studio` | Pracownia. |

### Odczyt API (JSON)

| Metoda | Ścieżka | Opis |
| --- | --- | --- |
| `GET` | `/api/identities` | Katalog tożsamości `public` (bez `unlisted`). |
| `GET` | `/api/identities/:ref` | Profil, zasoby, projekty, klucze publiczne, granty i stan dziennika. |
| `GET` | `/api/identities/:ref/projects` | Projekty danej tożsamości. |
| `GET` | `/api/identities/:ref/projects/:project_id` | Szczegóły projektu i jego zasoby. |
| `GET` | `/api/identities/:ref/access/:key` | Informacja o uprawnieniach klucza. **Nie jest to token zapisu.** |
| `GET` | `/api/identities/:id/head` | Numer i ID ostatniego zdarzenia. |
| `GET` | `/api/identities/:id/events?after=N` | Podpisane koperty zdarzeń od podanego miejsca. |
| `GET` | `/api/identities/:id/events/:event_id` | Sprawdzenie, czy konkretne zdarzenie znajduje się w dzienniku. |
| `GET` | `/api/identities/:ref/resources/:resource_id/download` | Pobranie pliku jako załącznika. |
| `GET` | `/blobs/:hash` | Bajty dostępnego, publicznie opublikowanego materiału. |

Parametr `:ref` może być uchwytem lub ID. W trasach `/head`, `/events` i wyszukiwaniu potwierdzenia zdarzenia `:id` oznacza **ID tożsamości**, nie jej uchwyt.

### Zapis i sesja

| Metoda | Ścieżka | Wymaganie | Opis |
| --- | --- | --- | --- |
| `POST` | `/api/events` | Podpisana koperta | Dopisanie zdarzenia, w tym utworzenie tożsamości. |
| `POST` | `/api/session/challenge` | Brak sesji | Przygotowanie wyzwania do logowania kluczem autoryzacji. |
| `POST` | `/api/session` | Podpis wyzwania | Utworzenie sesji i zwrócenie tokenu CSRF. |
| `GET` | `/api/me` | Sesja | Dane bieżącej sesji. |
| `DELETE` | `/api/session` | Sesja i CSRF | Zakończenie sesji. |
| `POST` | `/api/blobs` | Sesja i CSRF | Przesłanie surowych bajtów pliku. |

Wysyłając blob, klient podaje typ materiału w `Content-Type`. Dla żądań wymagających CSRF przesyła także nagłówek `x-csrf-token`. Samo wrzucenie bloba **nie tworzy publikacji**: potrzebne jest późniejsze `resource.put`.

### Przykłady odczytu

```sh
# Publiczny profil
curl http://localhost:4000/api/identities/PRZYKLADOWY_UCHWYT

# Ostatnie zdarzenie (ID, nie uchwyt)
curl http://localhost:4000/api/identities/ID_TOZSAMOSCI/head

# Projekty
curl http://localhost:4000/api/identities/PRZYKLADOWY_UCHWYT/projects
```

## Podpisane zdarzenia

Zdarzenia są przesyłane do `POST /api/events` jako JSON. Przykładowy **kształt** koperty:

```json
{
  "payload": "BASE64URL_PODPISANEGO_JSON",
  "signer": "ID_KLUCZA_SYGNOWANIA",
  "signature": "BASE64URL_PODPISU"
}
```

W wersji koperty **v2** mogą występować też `attachments`: tekstowe załączniki potrzebne do zapisu pól profilu lub metadanych. Nie są one częścią trwałego dziennika.

Po zdekodowaniu `payload` zawiera między innymi: `v`, `signer`, `identity`, `seq`, `prev`, `type`, `body` i `ts`. Przykładowe typy operacji:

| Typ | Działanie |
| --- | --- |
| `identity.genesis` | Utworzenie tożsamości. |
| `profile.update`, `identity.visibility.set` | Zmiana profilu lub widoczności. |
| `project.create`, `project.update`, `project.delete` | Utworzenie, zmiana i usunięcie projektu. |
| `resource.put`, `resource.delete` | Dodanie, aktualizacja, przeniesienie lub usunięcie zasobu. |
| `grant.create`, `grant.revoke` | Nadanie albo cofnięcie grantu. |
| `key.add`, `key.revoke`, `auth_key.add`, `auth_key.revoke` | Operacje na kluczach. |

Kopertę można przygotować przez CLI. Nie da się stworzyć prawidłowego podpisu, podmieniając tekst w przykładowym JSON-ie.

Przyjęty zapis zwraca `201 Created` i dane zdarzenia, np. jego `id`, `identity`, `seq` i `type`. Następne zdarzenie musi wskazać właściwą głowę dziennika przez `seq` i `prev`.

## Autoryzacja

**Odczyt** katalogu, profilu, projektów i historii nie wymaga sesji. Dotyczy to również `unlisted`, jeśli zna się adres.

**Podpisywanie zmian** jest niezależne od cookie: serwer sprawdza podpis Ed25519 i uprawnienia klucza. 
Założyciel ma pełny dostęp w swojej tożsamości; współpracownik działa w granicach grantów.

**Upload plików** wymaga sesji uzyskanej po podpisaniu wyzwania kluczem autoryzacji. 
Sesja nie zastępuje podpisu `resource.put`.

Przy zamkniętej rejestracji utworzenie tożsamości przez HTTP wymaga ważnego zaproszenia w nagłówku `x-oktavarium-invite`.
Operator może też wczytać podpisane zdarzenie lokalnie.

## Błędy

API zwraca kod HTTP i czytelny kod błędu:

```json
{
  "error": {
    "code": "bad_seq",
    "expected_seq": 4
  }
}
```

Najczęstsze sytuacje:

| HTTP | Przykładowy kod | Znaczenie |
| --- | --- | --- |
| `400` | `invalid_envelope` | Niepoprawna koperta albo podpis. |
| `401` | `unauthenticated` | Brak potrzebnej sesji. |
| `403` | `not_authorized`, `registration_closed` | Brak prawa do operacji lub zamknięta rejestracja. |
| `404` | `unknown_identity`, `unknown_project`, `event_not_found` | Nie znaleziono wskazanego obiektu. |
| `409` | `bad_seq`, `bad_prev`, `project_slug_taken`, `resource_path_taken` | Konflikt z aktualnym stanem. |
| `413` / `415` | `too_large`, `unsupported_media_type` | Za duży plik lub niewspierany format. |
| `422` | `invalid_body`, `invalid_window` | Nieprawidłowe dane operacji. |

`event_not_found` oznacza, że zdarzenie nie zostało znalezione w chwili odczytu. Po utraconej odpowiedzi nie jest to jeszcze pewny dowód, że wcześniejszy zapis nie dotrze.

## Ograniczenia

- Instancja jest przewidziana dla małej społeczności. Nie ma federacji ani automatycznej replikacji.
- Własne strony HTML/CSS/JS działają tylko przy skonfigurowanej domenie stron (`OKTAVARIUM_SITES_DOMAIN`).
- API nie zapewnia prywatności profili ani dzienników. `unlisted` to brak wyświetlania w katalogu, nie kontrola odczytu.
- Nie ma pełnego systemu automatycznego ograniczania liczby żądań; publiczny serwer wymaga dodatkowej ochrony operatora.
- Zapis danych do bazy i blobów jest serializowany, przez co współbieżność zapisów jest ograniczona do niezależnych dzienników.

Przy wdrożeniu produkcyjnym wymagane zmienne: 
`DATABASE_PATH` (ścieżka pliku SQLite),
`SECRET_KEY_BASE`; 
opcjonalne: 
`PHX_HOST`, `PORT`, `POOL_SIZE`, 
`OKTAVARIUM_REGISTRATION`, 
`OKTAVARIUM_BLOB_DIR`, 
`OKTAVARIUM_SITES_DOMAIN`.
