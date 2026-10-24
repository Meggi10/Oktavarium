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

Przeglądarka generuje pary Ed25519, szyfruje lokalny skarbiec, 
buduje kopertę zdarzenia i podpisuje dokładne bajty `payload`. 
Do serwera trafiają klucze **publiczne**, podpisy, podpisane payloady i jawnie przesłane treści/pliki. 
Serwer sprawdza uprawnienia i nigdy nie otrzymuje prywatnych kluczy ani hasła skarbca. 
`/login` odblokowuje skarbiec lokalnie; osobne `/api/session` służy tylko do uzyskania sesji przesyłania blobów. 
Publiczny katalog jest początkowo renderowany jako HTML LiveView i działa bez JS; 
z JS może utrzymywać połączenie `/live` do filtrowania i zmiany układu. 
To połączenie nie zastępuje podpisanego REST API do publikacji.

## Zasoby

| Zasób | Identyfikator | Operacje |
| ----- | ------------- | -------- |
| Tożsamość | Skrót genesis jako ID base64url; opcjonalny uchwyt, `person`/`collective`, `public`/`unlisted` | Genesis, profil, widoczność, klucze, granty, projekty i zasoby. |
| Dziennik | Osobny łańcuch per ID, `seq` od zera, poprzednik `prev`; ID zdarzenia to skrót podpisanego payloadu | Publiczny odczyt głowy, kopert i potwierdzenia pojedynczego zdarzenia; dopisywanie kopert. |
| Projekt | Trwałe ID z `project.create`, zmienny `slug`, metadane i własne pliki | Utworzenie, zmiana, usunięcie pustego projektu. |
| Plik/zasób | Trwałe ID, `path` i opcjonalny `project_id`, skrót SHA-256 bajtów, rozmiar, MIME, metadane | Publikacja/zmiana/przeniesienie przez `resource.put`, usunięcie referencji przez `resource.delete`; publiczny odczyt/pobranie. |
| Blob | 64-znakowy małoliterowy SHA-256, bajty poza SQLite | Upload po sesji, strumieniowany publiczny odczyt opublikowanego obrazu/audio, bezpieczny download źródła. |
| Grant | ID, podpisujący wystawca, klucz odbiorcy, akcja, ścieżka, granice czasu, opcjonalne delegowanie/rodzic | Podpisane `grant.create` / `grant.revoke`, publiczna analiza dostępu. |
| Sesja / zaproszenie | Losowe tokeny przechowywane na serwerze jako skróty | Krótka sesja uploadu; token zaproszenia uprawniający tylko do genesis przy rejestracji `closed`. |

Tekstowe wartości w `profile.update` oraz metadanych `project.create`, `project.update`, `resource.put` są w payloadzie zastępowane referencjami `{"sha256":"..."}`. Pole `attachments` w przesyłanej kopercie może przenieść odpowiadające im bajty UTF-8; serwer sprawdza ich hash i zapisuje w blobach, lecz nie przechowuje attachments w tabeli zdarzeń. `null` usuwa pole profilu. Historyczne skróty, ścieżki, typy i klucze pozostają w dzienniku.

## Endpointy

Prefiks `/api` oznacza JSON. Odczyt jest publiczny również dla tożsamości `unlisted` znanej po adresie; jej rekord nie trafia do indeksu. `:ref` przy profilach i projektach oznacza uchwyt lub ID. Dziennik przyjmuje **ID tożsamości** jako `:id`, nie uchwyt. Wszystkie zapisy stanu poza genesis to podpisane `POST /api/events`, nie osobne `PATCH`/`DELETE` dla profilu i plików.

### API (JSON)

| Metoda i adres | Żądanie / odpowiedź | Dostęp |
| --- | --- | --- |
| `POST /api/events` | Koperta `{payload, signer, signature, attachments?}`; `201 {id, identity, seq, type}`. | Publiczne HTTP; reguły podpisu, łańcucha, grantów; genesis w `closed` wymaga `X-Oktavarium-Invite`. |
| `GET /api/identities` | `{identities:[{id, handle, kind, display_name, avatar_url}]}`; indeks tylko `public`. | Publiczny. |
| `GET /api/identities/:ref` | Profil, `profile_refs`, widoczność, klucze, członkowie, granty, zasoby, projekty, `site_url`, `integrity`, głowa. | Publiczny, również bezpośredni `unlisted`. |
| `GET /api/identities/:ref/projects` | `{identity, projects:[...]}`. | Publiczny. |
| `GET /api/identities/:ref/projects/:project_id` | `{identity, project:{id,slug,meta,meta_refs,site_url,scope}, resources:[...]}`. | Publiczny. |
| `GET /api/identities/:ref/access/:key` | Migawka uprawnień klucza `{identity,key,signing_key,founder,grants,checked_at}`; `Cache-Control: no-store`. | Publiczny; nie jest tokenem uprawniającym do zapisu. |
| `GET /api/identities/:id/head` | `{identity,seq,id}` ostatniego zdarzenia. | Publiczny. |
| `GET /api/identities/:id/events?after=N` | `{identity,head,events:[{payload,signer,signature}]}`; bez `after` od genesis, z `after` po numerze `N ≥ 0`. | Publiczny; bez limitu strony. |
| `GET /api/identities/:id/events/:event_id` | `{id,identity,seq,type,envelope:{payload,signer,signature}}` dla dokładnej pary; `Cache-Control: no-store`; brak → `404 event_not_found`. | Publiczny; służy do sprawdzenia niepewnego wyniku zapisu. |
| `POST /api/session/challenge` | Bez parametrów; `{nonce,host,message,expires_at}`. | Publiczny. |
| `POST /api/session` | `{nonce,key,signature}` → `{key,csrf,identities:[...]}` i ciasteczko. | Aktywny klucz `auth` powiązany z tożsamością. |
| `GET /api/me` | `{key,csrf,identities:[...]}` lub `401 unauthenticated`. | Sesja uploadowa. |
| `DELETE /api/session` | `{ok:true}`. | Sesja i nagłówek `X-CSRF-Token`. |
| `POST /api/blobs` | **Surowe bajty**, `Content-Type` i `X-CSRF-Token`; `201 {hash,size,media_type}`. Nie jest to JSON ani multipart. | Sesja i CSRF. |
| `GET /api/identities/:ref/resources/:resource_id/download` | Bajty źródłowe z `Content-Disposition: attachment` i `application/octet-stream`; brak → `404 unknown_resource`. | Publiczny, także dla źródeł HTML/JS/SVG. |

Odpowiedź szczegółów tożsamości ma `auth_keys:[{key_id,status}]`, `members:[{key_id,label,status}]`, 
`grants` z akcją, zakresem, wystawcą, odbiorcą, rodzicem, 
`status` i datami, `resources` z `available`, `kind`, `path`, 
`project_id`, `hash`, `size`, `media_type`, `meta`, `meta_refs`. 
`projects` zawiera ID, slug, meta, meta_refs, URL strony. 
Wartość `integrity` to `"ok"` lub `"error"`. Stan `unlisted` jest metadanym, nie bramką dostępu.

### Minimum integracyjne z wymagań projektowych (s. 19)

Ważnym zasobem są **projekty**. 
Operacje faktycznie zapisują stan w SQLite, lecz API publikacji jest dziennikiem podpisanych komend, 
zamiast osobnym kontrolerem REST dla każdej metody HTTP:

| Zadanie użytkownika | Wywołanie HTTP z Pracowni | Efekt i odświeżenie UI |
| --- | --- | --- |
| Odczyt | `GET /api/identities/:ref/projects` lub szczegóły `GET .../projects/:project_id` | `assets/js/lib/api.ts` obsługuje żądanie i odpowiedź JSON do widoku; pusta lista ma komunikat. |
| Utworzenie | `POST /api/events` z typem `project.create` | Trwałe ID i projekt w projekcji; Pracownia ponownie pobiera szczegóły. |
| Aktualizacja | `POST /api/events` z typem `project.update` | Zmiana slug/metadanych po sprawdzeniu podpisu i uprawnienia; klient odświeża stan. |
| Usunięcie | `POST /api/events` z typem `project.delete` | Usunięcie pustego projektu z projekcji, wpis pozostaje w dzienniku; UI odświeża listę. |

Warstwa `assets/js/lib/api.ts` jest oddzielona od kodu formularzy i kompilowana do `/assets/js/lib/api.js`. 
Typuje opcje żądania, błędy i nierozstrzygniętą próbę publikacji. 
Klient ma timeouty `AbortSignal.timeout`, kody błędów mapowane na polskie komunikaty, 
stany ładowania/pustego wyniku w Pracowni i ponowne odczytanie stanu po zapisie. 
Niepewny wynik POST jest sprawdzany po identyfikatorze zdarzenia; 
konflikt sekwencji nie podpisuje automatycznie innej operacji. 

Klient deklaruje modele DTO w `assets/js/lib/models.ts`; 
przed użyciem katalogu, szczegółów tożsamości, migawki dostępu i historii 
sprawdza podstawowy kształt JSON i odrzuca nieprawidłową projekcję. 
Odpowiedzi sesji, uploadu, potwierdzeń oraz osobnych tras projektowych mają typy TS, 
lecz nie osobne dekodery runtime; serwer pozostaje autorytatywny dla walidacji zapisu. 

Parametry `view`, `before`, `after` i `ref` mają konkretne znaczenie; 
nie istnieje dowolna wyszukiwarka `q`. 
Slajd minimum integracyjnego używa nazwy `docs/03-api.md`, 
podczas gdy wymagany układ dokumentów z etapu przygotowania 
wskazuje `docs/04-api.md`; tutaj zachowano ten drugi układ.

#### `POST /api/events`

`payload` jest base64url bez paddingu i dekoduje się do 
**dokładnych bajtów JSON** podpisanych Ed25519 w domenie `oktavarium/event/v1\0`. 
Wewnątrz ma pola `v:2`, `signer`, `identity`, `seq`, `prev`, `type`, `body`, `ts` (sekundy Unix). 
`signer` na zewnątrz to base64url 32-bajtowego klucza publicznego, 
`signature` to base64url 64-bajtowego podpisu. 
Genesis ma `identity:null`, `seq:0`, `prev:null`, a ID tożsamości jest ID tego zdarzenia. 
Pozostałe zdarzenia wskazują ID tożsamości, kolejny numer i ID poprzednika. 
Sposób serializacji payloadu wpływa na podpis i ID, 
więc klient nie może go ponownie zakodować między podpisem a wysyłką.

Serwer obsługuje 14 typów: 
`identity.genesis`, `identity.visibility.set`, `profile.update`, `grant.create`, 
`grant.revoke`, `key.add`, `key.revoke`, `auth_key.add`, `auth_key.revoke`, 
`project.create`, `project.update`, `project.delete`, `resource.put`, `resource.delete`. 
Dla `resource.put` blob musi być już zapisany i musi odpowiadać deklarowanemu hash/rozmiarowi/MIME.

#### `GET /api/identities/:id/head`

Wynik `seq` i `id` służy do przygotowania następnego zdarzenia (`seq + 1`, `prev = id`). 
Dwa niezależne zapisy o tym samym numerze nie tworzą gałęzi; jeden może otrzymać konflikt `bad_seq`.

#### `GET /api/identities/:id/events?after=N`

Zwraca koperty bez `attachments`, bo bajty tekstu są przechowywane osobno. 
Należy sprawdzić podpisy, ID i łańcuch, a następnie podążyć za `head`, jeśli odczyt ma obejmować cały dziennik. 
`after` jest numerem sekwencji, nie identyfikatorem zdarzenia.

### Strony (HTML)

| Adres | Znaczenie |
| --- | --- |
| `/` oraz `?view=all/images/audio/projects/people` | Katalog LiveView: początkowy HTML, adresy filtrów, opcjonalna aktualizacja po WebSocket. |
| `/i/:ref` | Publiczny profil z historią; `?before=N` dla wcześniejszych zdarzeń (50 na stronę). |
| `/i/:ref/projects/:project_id` | Publiczna strona projektu. |
| `/join`, `/login`, `/studio` | Powłoki aplikacji przeglądarkowej; wymagają JS. |
| `/blobs/:hash` | Tylko obecnie opublikowany obraz/audio, `200` albo `206` dla `Range`, `416` dla błędnego zakresu; inne hashe → `404`. |
| `<handle>.<sites_domain>/*` i `p-<base32-id>.<sites_domain>/*` | Strona tożsamości/projektu z plików `site/`, jeśli skonfigurowano domenę i index; `GET`/`HEAD`, `304` na ETag, inne metody `405`. |

Host tożsamości wymaga uchwytu zgodnego z DNS (małe litery/cyfry/myślnik, 2–32 znaki); 
poprawny uchwyt zawierający `_` nadal nadaje się na profil, ale nie na subdomenę. 
Host projektu koduje jego trwałe ID, zatem zmiana slug nie zmienia adresu strony. 
Na hoście strony nie ma API głównej aplikacji; inline JS blokuje CSP, 
a pliki CSS/JS z tej strony mogą działać w osobnym origin.

`/live` jest gniazdem Phoenix LiveView dla katalogu, 
nie endpointem JSON ani publicznym interfejsem do dopisywania zdarzeń. 
Filtry `?view=` są nadal zwykłymi adresami HTTP. 
Token CSRF w dokumencie umożliwia połączenie LiveView; 
nie jest tokenem `X-CSRF-Token` sesji uploadowej wydawanym przez `POST /api/session`.

### Przykład użycia

Zakładając wcześniej utworzoną podpisaną kopertę CLI w `events/ja-0.json` i otwartą rejestrację:

```sh
curl -H 'Content-Type: application/json' --data-binary @events/ja-0.json \
  http://localhost:4000/api/events

curl http://localhost:4000/api/identities/ID_TOZSAMOSCI/head
curl 'http://localhost:4000/api/identities/ID_TOZSAMOSCI/events?after=0'
curl http://localhost:4000/api/identities/ID_TOZSAMOSCI/events/ID_ZDARZENIA
```

Przy `closed` genesis wymaga dodatkowo `-H 'X-Oktavarium-Invite: TOKEN'`. Do uploadu potrzeba odpowiedzi na wyzwanie podpisanej **kluczem autoryzacji**, ciasteczka i wartości CSRF; samo przesłanie bajtów nie publikuje pliku. Przeglądarka wykonuje tę sekwencję automatycznie po potwierdzeniu operacji.

## Błędy

Błędy domenowe mają kształt `{"error":{"code":"...", ...}}`. 
Przykłady: `400 invalid_envelope` z `reason`; 
`401 unauthenticated`, `invalid_challenge`, `bad_signature`, `unknown_key`; 
`403 not_authorized` (czasem `field`), `registration_closed`, `invalid_invite`, `invalid_csrf`, `broken_chain`; 
`404 unknown_identity`, `unknown_project`, `unknown_resource`, `blob_not_found` albo `event_not_found` przy potwierdzeniu; 
`409 bad_seq` z `expected_seq`, `duplicate_event`, `bad_prev`, `project_slug_taken`, `resource_path_taken`; 
`413 too_large`; 
`415 unsupported_media_type`/`media_type_mismatch`; 
`422 invalid_body` z `field`, `content_missing` z `detail`. 
Odrzucenie przez sam framework (np. limit parsera JSON lub niepasująca trasa) 
może mieć inny kod błędu niż walidacja domenowa.

Brak potwierdzenia HTTP po wysłaniu podpisanego zdarzenia **nie dowodzi**, że serwer je odrzucił. 
Klient sprawdza `GET .../events/:event_id` i porównuje całą kopertę. 
Gdy zdarzenia nie widać, może bezpiecznie ponowić dokładnie tę samą kopertę; 
przy konflikcie sekwencji trzeba pobrać głowę i ponownie zatwierdzić nowy zapis.

## Autoryzacja

Do czytania nie potrzeba konta, ciasteczka ani sesji. 
`POST /api/events` ufa wyłącznie podpisanej kopercie, aktywnemu członkostwu klucza i ważnemu zakresowi grantu. 
Założyciel ma pełny zakres we własnej tożsamości; 
granty mogą ograniczać akcje i ścieżki oraz być dalej delegowane tylko po spełnieniu warunków rodzica. 
Czasy grantów liczy zegar serwera. 
Genesis w trybie zamkniętym jest wyjątkiem: 
jednorazowy token zaproszenia trafia w nagłówku, a zużycie i zapis są atomowe w SQL.

`POST /api/session/challenge` wydaje ważny przez 300 sekund nonce powiązany z hostem. 
Klient podpisuje `host + "\n" + nonce` domeną logowania, a `POST /api/session` konsumuje wyzwanie. 
Sesja trwa do 7 dni, zapisuje tylko skrót losowego tokenu i przestaje działać po 
cofnięciu wszystkich aktywnych powiązań klucza `auth`. `DELETE /api/session` i `POST /api/blobs` 
wymagają poprawnego `X-CSRF-Token`. 
Odblokowanie skarbca w przeglądarce samo nie zakłada takiej sesji.

## Ograniczenia wybranego rozwiązania

| Obszar | Rzeczywisty skutek |
| --- | --- |
| SQLite / pojedyncza instancja | Zapisy się szeregują. Brak pomiarów obciążenia i replikacji/federacji. |
| Dziennik i treści | Podpisy oraz hash tekstu pozostają, ale usuniętych bajtów nie da się odtworzyć z samego logu; `resource.delete` usuwa referencję, nie automatycznie plik bloba. |
| Indeks i historia | Brak wyszukiwania `q`, paginacji katalogu i limitu stron w REST API dziennika; HTML profil pokazuje 50 wpisów na stronę. |
| Ochrona usługi | Kod nie ogranicza częstotliwości wyzwań, uploadów ani innych żądań. Publiczny odczyt `unlisted` nadal ujawnia dane znającym adres. |
| Strony WWW | Potrzebna osobna domena DNS i konfiguracja; bez niej `site_url` jest `null`. Serwowanie ogranicza się do opublikowanych ścieżek i wybranych MIME. |
