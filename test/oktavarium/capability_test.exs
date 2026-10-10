defmodule Oktavarium.CapabilityTest do
  use ExUnit.Case, async: true

  alias Oktavarium.Capability

  defp cap(action, resource), do: %{action: action, resource: resource}

  describe "walidacja wzorców" do
    test "akcje" do
      for ok <- ["*", "project.edit", "project.*", "a.b.c", "a.b.*"] do
        assert Capability.valid_action?(ok), ok
      end

      for bad <- ["", ".", "a..b", "*.edit", "pro*ject", "a.*.b", nil, :atom, 5] do
        refute Capability.valid_action?(bad), inspect(bad)
      end
    end

    test "zasoby" do
      for ok <- ["id1", "id1/*", "id1/lang/pl", "id1/lang/*", "*"] do
        assert Capability.valid_resource?(ok), ok
      end

      for bad <- ["", "/", "id1//pl", "id1/*/pl", "id1/l*g", nil, 5] do
        refute Capability.valid_resource?(bad), inspect(bad)
      end
    end
  end

  describe "covers?/2 — akcje" do
    test "gwiazdka obejmuje wszystko" do
      assert Capability.covers?(cap("*", "id/*"), cap("project.edit", "id/x"))
      assert Capability.covers?(cap("*", "id/*"), cap("*", "id/x"))
    end

    test "prefiks z gwiazdką obejmuje podakcje i węższe wzorce" do
      parent = cap("project.*", "id/*")
      assert Capability.covers?(parent, cap("project.edit", "id/x"))
      assert Capability.covers?(parent, cap("project.lang.edit", "id/x"))
      assert Capability.covers?(parent, cap("project.lang.*", "id/x"))
      assert Capability.covers?(parent, cap("project.*", "id/x"))
    end

    test "prefiks nie obejmuje szerszych ani obcych akcji" do
      parent = cap("project.*", "id/*")
      refute Capability.covers?(parent, cap("*", "id/x"))
      refute Capability.covers?(parent, cap("projects.edit", "id/x"))
      refute Capability.covers?(parent, cap("project", "id/x"))
      refute Capability.covers?(parent, cap("profile.edit", "id/x"))
    end

    test "dokładna akcja obejmuje tylko siebie" do
      parent = cap("project.edit", "id/*")
      assert Capability.covers?(parent, cap("project.edit", "id/x"))
      refute Capability.covers?(parent, cap("project.delete", "id/x"))
      refute Capability.covers?(parent, cap("project.*", "id/x"))
    end
  end

  describe "covers?/2 — zasoby" do
    test "ogon z gwiazdką obejmuje korzeń i potomków" do
      parent = cap("*", "id/*")
      assert Capability.covers?(parent, cap("a", "id"))
      assert Capability.covers?(parent, cap("a", "id/lang"))
      assert Capability.covers?(parent, cap("a", "id/lang/pl"))
      assert Capability.covers?(parent, cap("a", "id/lang/*"))
    end

    test "inna tożsamość nie jest objęta" do
      parent = cap("*", "id/*")
      refute Capability.covers?(parent, cap("a", "inne"))
      refute Capability.covers?(parent, cap("a", "inne/lang"))
      refute Capability.covers?(parent, cap("a", "id2/lang"))
    end

    test "węższy zasób nie obejmuje szerszego" do
      parent = cap("*", "id/lang/pl")
      assert Capability.covers?(parent, cap("a", "id/lang/pl"))
      refute Capability.covers?(parent, cap("a", "id/lang/*"))
      refute Capability.covers?(parent, cap("a", "id/lang"))
      refute Capability.covers?(parent, cap("a", "id/lang/pl/x"))
    end

    test "gwiazdka w środku nie jest interpretowana" do
      refute Capability.covers?(cap("*", "id/*/pl"), cap("a", "id/lang/pl"))
    end

    test "niepoprawne wzorce nigdy nie dają uprawnień" do
      refute Capability.covers?(cap("pro*ject", "id/*"), cap("pro*ject", "id/x"))
      refute Capability.covers?(cap("*", ""), cap("a", "id"))
    end
  end
end
