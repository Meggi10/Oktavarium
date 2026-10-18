# 06. Praca zespołowa

Dokument opisuje podział odpowiedzialności w dwuosobowym zespole oraz zasady pracy z repozytorium: branche, pull requesty i review.
Należy go bardziej traktować jako propozycję, bo praktyka tak czy siak wyjdzie w praniu.

## Podział pracy

Pracę przy projekcie można podzielić na takie obszary:

| Obszar | Zadania między innymi | Kto odpowiadał |
| ------ | --------------------- | -------------- |
| **Projekt i UX** | Zbieranie wymagań, rozpisanie scenariuszy, makiety, sprawdzanie widoków na komputerze. | Magda i Piotr |
| **Frontend**  | Widoki publiczne, Pracownia, formularze, komunikaty i CSS. | Magda |
| **Backend** | Tożsamości, uprawnienia, podpisy, projekty, API i baza danych. | Piotr |
| **Testy i stabilizacja** | Testy automatyczne, scenariusze w przeglądarce, naprawa błędów. | Magda i Piotr |
| **Dokumentacja** | Opis funkcjonalności i aktualizacja plików `docs/` po zakończeniu zmian w kodzie. | Piotr |

## Branche

Dobrą praktyką byłoby robienie większych zmian na osobnej gałęzi, np. `feature/projekty` albo `fix/pracownia`,
a potem łączenie ich z główną wersją aplikacji.
Nie jest to jednak historia MVP tego repozytorium, ale sposób pracy, który warto stosować przy kolejnych zmianach.

## Pull Requesty

Przed połączeniem większej zmiany warto przejrzeć:

1. Co zmieniono i dlaczego.
2. Jak sprawdzić działanie.
3. Czy zmieniły się dane, API albo podpisy.
4. Czy są nowe testy lub znane ograniczenia.

Nie zakładamy, że każda dotychczasowa zmiana była wykonana przez Pull Request.

## Review

Druga osoba powinna sprawdzić przede wszystkim zachowanie użytkownika i miejsca,
w których łatwo o błąd:
utratę dostępu do skarbca, niechciane nadanie uprawnień, publikację bez potwierdzenia lub nieczytelny komunikat.

Przy pracy technicznej warto uruchomić:

```sh
mix test
node --test test/js/*_test.mjs
```

Zmiany interfejsu dobrze jest dodatkowo obejrzeć na komputerze. 
Testy automatyczne nie zastępują zwykłego przejścia przez formularz.

## Organizacja

W kolejnych etapach projektu zajmowaliśmy się następującymi tematami:

- wstępny prototyp modelu danych, kluczy kryptograficznych i tożsamości w CLI
- porządkowanie modelu danych, treści, projektów i uprawnień.
- opracowanie UX: najpierw publiczne widoki, potem Pracownia, na końcu formularze, podpisy i błędy.
- wdrożenie w Phoenix/HEEx i JavaScripcie oraz poprawki po testach lokalnych.
- stabilizacja poprzez sprawdzanie testów i naprawa zauważonych problemów, porządkowanie kodu i formatowanie.
- spisanie faktycznego stanu repozytorium w dokumentacji.
