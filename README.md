# Oktavarium
Pseudo-anonimowa aplikacja webowa oparta o kryptograficzne tożsamości.
Lokalnie hostowalna, ma służyć małym społecznościom artystów/programistów potrzebujących własnego miejsca do wspólnej kolaboracji.
Wszystko do odczytu jest otwarte, wszelkie zmiany stanu są za pośrednictwem operacji kryptograficznych.
Model danych jest z założeń podobny do systemu kontroli wersji, aniżeli do tradycyjnej aplikacji webowej.

## Autorzy
- *Magdalena Leśniewska* (u-20090)
- *Piotr Szymczak* (u-20714)

## Licencja
Projekt jest dostępny pod licencją MIT.

## Jak uruchomić
Potrzebne jest zainstalować `>=erlang::27.3.4` i `>=elixir::1.18.4` w środowisku.

```
mix_setup
mix phx.server
```
Dostępny spod [`localhost:4000`](http://localhost:4000) w przeglądarce.
