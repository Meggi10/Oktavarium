defmodule Oktavarium.Identities.ProfileTest do
  use ExUnit.Case, async: true

  alias Oktavarium.Identities.Profile

  describe "fields/0, action/0, resource/2" do
    test "zamknięty zestaw pól i nazwa akcji" do
      assert Profile.fields() == ["bio", "display_name", "location", "website"]
      assert Profile.action() == "profile.update"
    end

    test "zasób to <id>/profile/<pole>" do
      assert Profile.resource("abc", "bio") == "abc/profile/bio"
    end
  end

  describe "parse_changes/1" do
    test "przyjmuje poprawne wartości i null" do
      changes = %{"display_name" => "Pelagia", "bio" => "linia 1\nlinia\t2", "location" => nil}
      assert {:ok, ^changes} = Profile.parse_changes(changes)
    end

    test "website musi być adresem http albo https" do
      assert {:ok, _} = Profile.parse_changes(%{"website" => "https://example.org/a?b=c"})
      assert {:ok, _} = Profile.parse_changes(%{"website" => "http://example.org"})

      for bad <- [
            "example.org",
            "ftp://example.org",
            "javascript:alert(1)",
            "https://",
            "https://a b.org",
            "//example.org"
          ] do
        assert {:error, {:invalid_body, "fields.website"}} =
                 Profile.parse_changes(%{"website" => bad}),
               bad
      end
    end

    test "zły kształt całości" do
      for bad <- [nil, %{}, [], "x", 5, [{"bio", "x"}]] do
        assert {:error, {:invalid_body, "fields"}} = Profile.parse_changes(bad), inspect(bad)
      end
    end

    test "nieznane pole" do
      assert {:error, {:invalid_body, "fields.admin"}} =
               Profile.parse_changes(%{"admin" => "tak"})

      assert {:error, {:invalid_body, "fields.admin"}} = Profile.parse_changes(%{"admin" => nil})
      assert {:error, {:invalid_body, "fields.Bio"}} = Profile.parse_changes(%{"Bio" => "x"})
    end

    test "nazwa pola z niedrukowalnymi bajtami nie trafia do komunikatu" do
      assert {:error, {:invalid_body, "fields.?"}} =
               Profile.parse_changes(%{<<0xFF, 0xFE>> => "x"})
    end

    test "zła wartość: typ, pusty tekst, limit długości" do
      for bad <- [5, true, ["x"], %{"a" => 1}, ""] do
        assert {:error, {:invalid_body, "fields.display_name"}} =
                 Profile.parse_changes(%{"display_name" => bad}),
               inspect(bad)
      end

      assert {:ok, _} = Profile.parse_changes(%{"display_name" => String.duplicate("ż", 80)})

      assert {:error, {:invalid_body, "fields.display_name"}} =
               Profile.parse_changes(%{"display_name" => String.duplicate("ż", 81)})

      assert {:ok, _} = Profile.parse_changes(%{"bio" => String.duplicate("a", 2000)})

      assert {:error, {:invalid_body, "fields.bio"}} =
               Profile.parse_changes(%{"bio" => String.duplicate("a", 2001)})
    end

    test "znaki sterujące; nowa linia tylko w bio" do
      assert {:error, {:invalid_body, "fields.display_name"}} =
               Profile.parse_changes(%{"display_name" => "a\nb"})

      assert {:error, {:invalid_body, "fields.display_name"}} =
               Profile.parse_changes(%{"display_name" => "a\tb"})

      assert {:error, {:invalid_body, "fields.location"}} =
               Profile.parse_changes(%{"location" => "a\rb"})

      for bad <- ["a\0b", "a\eb", "a\rb", "a\u007Fb", "a\u0085b"] do
        assert {:error, {:invalid_body, "fields.bio"}} = Profile.parse_changes(%{"bio" => bad}),
               inspect(bad)
      end

      assert {:error, {:invalid_body, "fields.bio"}} = Profile.parse_changes(%{"bio" => <<0xFF>>})
    end

    test "błąd wskazuje pierwsze złe pole alfabetycznie" do
      assert {:error, {:invalid_body, "fields.bio"}} =
               Profile.parse_changes(%{"bio" => "", "display_name" => "", "zzz" => "x"})
    end
  end

  describe "apply_changes/2" do
    test "ustawia, nadpisuje i usuwa, resztę zostawia" do
      profile = %{"display_name" => "Pelagia", "bio" => "stare", "location" => "Warszawa"}

      assert Profile.apply_changes(profile, %{
               "bio" => "nowe",
               "location" => nil,
               "website" => "https://a.pl"
             }) ==
               %{"display_name" => "Pelagia", "bio" => "nowe", "website" => "https://a.pl"}
    end

    test "usunięcie nieistniejącego pola i brak profilu" do
      assert Profile.apply_changes(%{}, %{"bio" => nil}) == %{}
      assert Profile.apply_changes(nil, %{"bio" => "x"}) == %{"bio" => "x"}
    end
  end
end
