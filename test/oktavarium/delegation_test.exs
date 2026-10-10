defmodule Oktavarium.DelegationTest do
  use ExUnit.Case, async: true

  alias Oktavarium.Delegation

  @t0 ~U[2026-01-01 00:00:00Z]
  @t1 ~U[2026-06-01 00:00:00Z]
  @t2 ~U[2026-12-01 00:00:00Z]

  defp grant(action, resource, opts \\ []) do
    %{
      action: action,
      resource: resource,
      not_before: opts[:not_before],
      expires_at: opts[:expires_at],
      revoked_at: opts[:revoked_at]
    }
  end

  describe "root/1" do
    test "obejmuje całą przestrzeń tożsamości i nic poza nią" do
      root = Delegation.root("id1")
      now = ~U[2026-10-05 12:00:00Z]

      assert Delegation.permits?(root, "project.delete", "id1", now)
      assert Delegation.permits?(root, "anything.at.all", "id1/lang/pl", now)
      refute Delegation.permits?(root, "project.delete", "id2", now)
    end
  end

  describe "delegate/2 — attenuation" do
    test "węższa capability jest dozwolona" do
      parent = grant("project.*", "id1/*")
      assert :ok = Delegation.delegate(parent, grant("project.edit", "id1/lang/pl"))
      assert :ok = Delegation.delegate(parent, grant("project.*", "id1/lang/*"))
      assert :ok = Delegation.delegate(parent, parent)
    end

    test "szersza akcja albo szerszy zasób to eskalacja" do
      parent = grant("project.edit", "id1/lang/*")

      assert {:error, :not_covered} =
               Delegation.delegate(parent, grant("project.*", "id1/lang/pl"))

      assert {:error, :not_covered} = Delegation.delegate(parent, grant("project.edit", "id1/*"))

      assert {:error, :not_covered} =
               Delegation.delegate(parent, grant("project.edit", "id2/lang/pl"))
    end
  end

  describe "delegate/2 — okno czasowe" do
    test "dziecko musi mieścić się w oknie rodzica" do
      parent = grant("*", "id1/*", not_before: @t0, expires_at: @t2)

      assert :ok =
               Delegation.delegate(parent, grant("a", "id1/x", not_before: @t1, expires_at: @t2))

      assert :ok =
               Delegation.delegate(parent, grant("a", "id1/x", not_before: @t0, expires_at: @t1))
    end

    test "wygasanie później niż rodzic albo bez wygasania jest zabronione" do
      parent = grant("*", "id1/*", expires_at: @t1)

      assert {:error, :window_exceeds_parent} =
               Delegation.delegate(parent, grant("a", "id1/x", expires_at: @t2))

      assert {:error, :window_exceeds_parent} = Delegation.delegate(parent, grant("a", "id1/x"))
    end

    test "start wcześniej niż rodzic albo bez startu jest zabroniony" do
      parent = grant("*", "id1/*", not_before: @t1)

      assert {:error, :window_exceeds_parent} =
               Delegation.delegate(parent, grant("a", "id1/x", not_before: @t0))

      assert {:error, :window_exceeds_parent} = Delegation.delegate(parent, grant("a", "id1/x"))
    end

    test "rodzic bez ograniczeń pozwala na dowolne okno" do
      parent = grant("*", "id1/*")

      assert :ok =
               Delegation.delegate(parent, grant("a", "id1/x", not_before: @t0, expires_at: @t1))
    end

    test "brak pokrycia ma pierwszeństwo przed oknem" do
      parent = grant("project.edit", "id1/*", expires_at: @t1)

      assert {:error, :not_covered} =
               Delegation.delegate(parent, grant("x.y", "id1/x", expires_at: @t2))
    end
  end

  describe "active_at?/2" do
    test "granice okna: start włącznie, koniec wyłącznie" do
      g = grant("*", "id1/*", not_before: @t1, expires_at: @t2)

      refute Delegation.active_at?(g, @t0)
      assert Delegation.active_at?(g, @t1)
      assert Delegation.active_at?(g, ~U[2026-09-01 00:00:00Z])
      refute Delegation.active_at?(g, @t2)
    end

    test "unieważnienie działa od chwili revoked_at" do
      g = grant("*", "id1/*", revoked_at: @t1)

      assert Delegation.active_at?(g, @t0)
      refute Delegation.active_at?(g, @t1)
      refute Delegation.active_at?(g, @t2)
    end

    test "grant bez ograniczeń jest zawsze aktywny" do
      assert Delegation.active_at?(grant("*", "id1/*"), @t0)
    end
  end

  describe "permits?/4" do
    test "wymaga jednocześnie aktywności i pokrycia" do
      g = grant("project.edit", "id1/lang/*", expires_at: @t1)

      assert Delegation.permits?(g, "project.edit", "id1/lang/pl", @t0)
      refute Delegation.permits?(g, "project.edit", "id1/lang/pl", @t2)
      refute Delegation.permits?(g, "project.delete", "id1/lang/pl", @t0)
      refute Delegation.permits?(g, "project.edit", "id1/readme", @t0)
    end
  end
end
