defmodule OktavariumWeb.ComponentsTest do
  use ExUnit.Case, async: true

  import OktavariumWeb.Components

  test "short/1 skraca długie identyfikatory i zostawia krótkie" do
    id = String.duplicate("a", 20) <> String.duplicate("b", 23)
    assert short(id) == "aaaaaa…bbbb"
    assert short("pelagia") == "pelagia"
    assert short("12345678901234") == "12345678901234"
  end

  test "plural/4 odmienia po polsku" do
    word = fn n -> plural(n, "zdarzenie", "zdarzenia", "zdarzeń") end

    assert word.(0) == "0 zdarzeń"
    assert word.(1) == "1 zdarzenie"
    for n <- [2, 3, 4, 22, 23, 24, 102], do: assert(word.(n) == "#{n} zdarzenia", "n=#{n}")

    for n <- [5, 11, 12, 13, 14, 15, 21, 25, 112, 113, 114],
        do: assert(word.(n) == "#{n} zdarzeń", "n=#{n}")
  end

  test "format_time/1 pisze po polsku w UTC, także z czasu naiwnego" do
    assert format_time(~U[2026-10-06 09:05:00Z]) == "6 paź 2026, 09:05 UTC"
    assert format_time(~N[2027-01-31 23:59:59]) == "31 sty 2027, 23:59 UTC"
  end

  test "from_unix/1" do
    assert from_unix(0) == ~U[1970-01-01 00:00:00Z]
    assert from_unix("x") == nil
    assert from_unix(nil) == nil
    assert from_unix(10 ** 30) == nil
  end

  test "kind_name/1" do
    assert kind_name(:user) == "użytkownik"
    assert kind_name("org") == "organizacja"
    assert kind_name(:project) == "projekt"
    assert kind_name("project") == "projekt"
    assert kind_name(:bot) == "maszyna"
    assert kind_name(:cokolwiek) == "tożsamość"
  end
end
