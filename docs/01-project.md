# 01. Projekt

## Temat

**Oktavarium** to pseudo-anonimowa, mała samohosotwana platforma (z dostępem na zaproszenie)
dla osób szukających indywidualnej bądź kolektywnej przestrzeni do prezentacji i kolaboracji.

Jej rdzeniem jest model danych, w którym **tożsamość to klucz kryptograficzny**,
a uprawnienia są **podpisywanymi zdanymi**.
Każda ważna operacja ma podpis i trafia do dziennika danej tożsamości.
Dzięki temu można sprawdzić co zostało zmienione, jakim kluczem i w jakich okolicznościach,
jak i odtworzyć całą projekcję bazy danych i stron WWW według stanu dzienników.

## Problem i potrzeba

Małe społeczności (artyści, zespoły, otwarty projekt kolaboracyjny)
zwykle składają swoją obecność z kilku usług: portfolio dla prezentacji, repozytoria kodu, kanały komunikacji, wiki/galerie.
Z tego wynikają powtarzające się kłopoty:

1. **Tożsamość i uprawnienia są cudze.**
    Konto istnieje, dopóki pozwala na to operator usługi.
    Przekazanie komuś części uprawnień 
    ("niech Magda poprawia opisy charakterystyk postaci, ale tylko do końca miesiąca")
    zwykle oznacza nadanie komuś pełnej roli albo dzielenie się hasłem.
2. **Brak dowodu, kto co zmienił.**
    Historia zmian profilu, uprawnień czy treści zależy od logów operatora i nie da się jej niezależnie sprawdzić.
    Niektóre platformy mogą nawet takich logów nie prowadzić, utrzymując jedynie obecny stan rzeczy, 
    albo pozwalając na zakłamanie jego stanu przez modyfikacje przez administratora.
    Jeżeli taki dziennik jest prowadzony, rzadko kiedy jest on publiczny do odczytu.
3. **Zależność od jednego dostawcy.**
    Przeniesienie społeczności na inną instancję albo odtworzenie jej po awarii (lub ataku)
    oznacza ręczne odbudowywanie ról, kanałów komunikacji, oraz utrata istniejących treści czy nawet dzienników.
    Jeżeli to platforma uległa awarii, często oznacza to też utrata istniejących kont.
4. **Uzależnienie od zasad użytkowania operatora usługi.**
    Jeżeli społeczność chce pracować na własnych zasadach, 
    pozostać całkowicie anonimowa jeśli trzeba,
    kontrolować to kto ma prawo wchodzić w interakcję ze społecznością,
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
* zarządzie kluczami, zaproszenia, autoryzacja/odblokowanie kluczy w przeglądarce;
* edycja profilu i zasobów w przeglądarce;
* zasoby tożsamości (obrazy, audio, HTML/CSS/JS);

Szczegóły i priorytety: [02-requirements.md](02-requirements.md).
