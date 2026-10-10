# 01. Projekt

## Temat

**Oktavarium** to pseudo-anonimowa, samohosotwana platforma (z dostępem na zaproszenie).
Jej rdzeniem jest model danych, w którym **tożsamość to klucz kryptograficzny**,
a uprawnienia są **podpisywanymi zdanymi**.

Każda tożsamość (osoba, organizacja, projekt) prowadzi własny **dziennik podpisanych zdarzeń**,
podobny do historii commitów w systemie kontroli wersji.
Tabele w bazie i strony WWW są tylko widokiem (projekcją) tych dzienników.

## Problem i potrzeba

Małe społeczności twórcze (grupa artystów, zespół gry, kolektyw muzyczny, otwarty projekt kolaboracyjny)
zwykle składają swoją obecność z kilku usług: portfolio, repozytoria kodu, kanały komunikacji, wiki/galerie.
Z tego wynikają powtarzające się kłopoty:

1. **Tożsamość i uprawnienia są cudze.**
    Konto istnieje, dopóki pozwala na to operator usługi.
    Przekazanie komuś części uprawnień 
    ("niech Magda poprawia opisy charakterystyk postaci, ale tylko do końca miesiąca")
    zwykle oznacza nadanie komuś pełnej roli albo dzielenie się hasłem.
2. **Brak dowodu, kto co zmienił.**
    Historia zmian profilu, uprawnień czy treści zależy od logów operatora i nie da się jej niezależnie sprawdzić.
    Niektóre platformy mogą nawet takich logów nie prowadzić, utrzymując jedynie obecny stan rzeczy.
    Jeżeli taki dziennik jest prowadzony, nie jest on publiczny do odczytu.
3. **Zależność od jednego dostawny.**
    Przeniesienie społeczności na inną instancję albo odtworzenie jej po awarii (lub ataku)
    oznacza ręczne odbudowywanie kont i ról, kanałów komunikacji, 
    oraz utrata istniejących treści czy nawet dzienników.
4. **Uzależnienie od zasad użytkowania operatora usługi.**
    Jeżeli społeczność chce pracować na własnych zasadach, pozostać całkowicie anonimowa jeśli trzeba,
    może być to niemożliwe na ogólnodostępnych platformach;
    nie wnikając w postępujące metody weryfikacji wieku, czy ograniczenia nałożone przez usługodawców,
    którzy chcąc nam coś sprzedać są administratorami danych wrażliwych.
5. **Bezpieczeństwo i moderacja aktywności.**
    To kwestia czasu aż w społeczności pojawią się aktorzy chcący jej zagrozić, 
    zakłócić porządek rzeczy czy sprowadzić na jej operatorów (i innych użytkowników) poważne problemy.
    Kontrola takiej aktywności w lokalnej społeczności wymaga jakiejś formy moderacji 
    kanałów komunikacji i autoryzacji uprawnień, 
    co zawsze jest kompromisem między wzrostem i stabilnością społeczności, 
    a alokacją jej zasobów na właściwą aktywność dla której powstała.

Oktavarium odpowiada na te kłopoty przez:

* **tożsamość niezależną od serwera**:
    identyfikator tożsamości to skrót jej pierwszego zdarzenia (genesis),
    a nie numer z cudzej bazy danych, więc zostawia drogę do federacji i przenoszenia instancji;
* **delegowanie uprawnień z zawężaniem** (attenuation):
    delegat dostaje dokładnie tyle, ile trzeba, na jak długo trzeba,
    i może (jeśli mu pozwolono) przekazać dalej tylko równe lub węższe uprawnienie;
* **uprawnienia kluczy kryptograficznych**:
    każda czynność zmieniająca stan instancji lub tożsamości stoi za macierzą uprawnień przypisanych
    do klucza podpisującego daną zmianę, co uwzględnia zaproszenia do platformy i zakładanie nowych tożsamości.
* **weryfikowalny dziennik**:
    każdą zmianę podpisano, a każdy może pobrać dziennik tożsamości i sprawdzić podpisy
    oraz ciągłość łańcucha bez zaufania do serwera;
    Takie społeczności działają na podstawie **zaufania** do jej użytkowników i operatorów, co wspiera model kluczy.
* **odbudowę stanu z dziennika**:
    baza i strony WWW są projekcją, więc można je sprawdzić i odtworzyć (`mix oktavarium.rebuild`);

## Grupa docelowa

| Odbiorca | Potrzeba | Rozwiązanie |
| -------- | -------- | ----------- |
| Artysta / twórca indywidualny | własna, trwała "wizytówka" bez zależności od platformy, dostępna online | tożsamość z profilem i publicznym dziennikiem |
| Organizacja, pracownia, zespół | wspólna przestrzeń kolaboracji z podziałem ról i uprawnień | klucze tożsamości, zasoby/repozytoria danej tożsamości, uprawnienia nadawane kluczom |
| Osoba techniczna / administrator | prosta instancja do samodzielnego hostowania | jedna aplikacja Elixir i plik SQLite, bez osobnego serwera bazy |
| Gość / odwiedzający | zobaczyć treści, kto tu działa działa i co się zmieniało | publiczne strony tożsamości bez logowania (projekcja), dzienniki zdarzeń |

Platforma jest z założenia **otwarta do odczytu**, **zamknięta do zapisu (invite-only)** i **mała**: 
tysiące, jak nie _setki_ użytkowników; (żart celowy).

## Zakres projektu

* rdzeń kryptograficzny (Ed25519, podpisane koperty zdarzeń, domeny podpisów);
* model uprawnień z delegowaniem i zawężaniem, unieważnianiem uprawnień;
* dziennik zdarzeń z trzema typami: założenie tożsamości, nadanie uprawnienia, zmiana profilu;
* CLI do budowania instancji, kluczy i podpisywania zdarzeń oraz do wysyłania ich na serwer;
* serwer HTTP: REST API do zapisu i odczytu dzienników oraz publiczne strony 
    (katalogi tożsamości oraz ich zasobów, profil tożsamości z uprawnieniami i historią);
* narzędzia operatora: wczytywanie kopert do bazy, sprawdzanie i odbudowa projekcji;
* zarządzie kluczami, zaproszenia, autoryzacja/logowanie w przeglądarce;
* edycja profilu w przeglądarce;
* zasoby tożsamości (obrazy, audio, HTML/CSS/JS, repozytoria GIT);

Szczegóły i priorytety: [02-requirements.md](02-requirements.md).
