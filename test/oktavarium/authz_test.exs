defmodule Oktavarium.AuthzTest do
  use ExUnit.Case, async: true

  alias Oktavarium.Authz

  @now ~U[2026-10-06 12:00:00Z]
  @past ~U[2026-01-01 00:00:00Z]
  @future ~U[2099-01-01 00:00:00Z]

  # F = klucz założycielski; A, B, C to kolejne ogniwa łańcucha delegowania
  @founding "F"

  defp grant(id, issuer, subject, parent, opts) do
    %{
      id: id,
      issuer_key_id: issuer,
      subject_key_id: subject,
      parent_grant_id: parent,
      action: Keyword.get(opts, :action, "project.*"),
      resource: Keyword.get(opts, :resource, "X/*"),
      not_before: Keyword.get(opts, :not_before),
      expires_at: Keyword.get(opts, :expires_at),
      revoked_at: Keyword.get(opts, :revoked_at),
      delegable: Keyword.get(opts, :delegable, false)
    }
  end

  defp child(action, resource, opts \\ []) do
    %{
      action: action,
      resource: resource,
      not_before: Keyword.get(opts, :not_before),
      expires_at: Keyword.get(opts, :expires_at),
      delegable: Keyword.get(opts, :delegable, false),
      parent_grant_id: Keyword.get(opts, :parent)
    }
  end

  # F --g1(project.*, X/*)--> A --g2(project.edit, X/lang/*)--> B --g3(project.edit, X/lang/pl)--> C
  defp chain(overrides \\ %{}) do
    [
      grant("g1", "F", "A", nil, [delegable: true] ++ Map.get(overrides, :g1, [])),
      grant(
        "g2",
        "A",
        "B",
        "g1",
        [action: "project.edit", resource: "X/lang/*", delegable: true] ++
          Map.get(overrides, :g2, [])
      ),
      grant(
        "g3",
        "B",
        "C",
        "g2",
        [action: "project.edit", resource: "X/lang/pl"] ++ Map.get(overrides, :g3, [])
      )
    ]
  end

  describe "authorize_issue/5 — klucz założycielski" do
    test "wystawia dowolny grant bez grantu nadrzędnego" do
      assert :ok = Authz.authorize_issue(child("*", "X/*"), "F", @founding, [], @now)
    end

    test "inny klucz bez grantu nadrzędnego nie ma władzy" do
      assert {:error, :not_authorized} =
               Authz.authorize_issue(child("a.b", "X/y"), "A", @founding, chain(), @now)
    end

    test "klucz założycielski nie wskazuje grantu nadrzędnego" do
      c = child("a.b", "X/y", parent: "g1")

      assert {:error, :unexpected_parent_grant} =
               Authz.authorize_issue(c, "F", @founding, chain(), @now)
    end
  end

  describe "authorize_issue/5 — delegowanie" do
    test "węższy grant na podstawie grantu delegable" do
      assert :ok =
               Authz.authorize_issue(
                 child("project.edit", "X/lang/pl", parent: "g1"),
                 "A",
                 @founding,
                 chain(),
                 @now
               )

      assert :ok =
               Authz.authorize_issue(
                 child("project.edit", "X/lang/de", parent: "g2"),
                 "B",
                 @founding,
                 chain(),
                 @now
               )

      assert :ok =
               Authz.authorize_issue(
                 child("project.edit", "X/lang/pl", parent: "g2", delegable: true),
                 "B",
                 @founding,
                 chain(),
                 @now
               )
    end

    test "grant równy rodzicowi też jest dozwolony" do
      assert :ok =
               Authz.authorize_issue(
                 child("project.*", "X/*", parent: "g1"),
                 "A",
                 @founding,
                 chain(),
                 @now
               )
    end

    test "tylko podmiot grantu nadrzędnego może go użyć" do
      c = child("project.edit", "X/lang/pl", parent: "g1")
      assert {:error, :not_authorized} = Authz.authorize_issue(c, "B", @founding, chain(), @now)

      assert {:error, :not_authorized} =
               Authz.authorize_issue(c, "stranger", @founding, chain(), @now)
    end

    test "nieznany grant nadrzędny" do
      c = child("project.edit", "X/lang/pl", parent: "nie-ma")

      assert {:error, :unknown_parent_grant} =
               Authz.authorize_issue(c, "A", @founding, chain(), @now)
    end

    test "grant bez delegable nie pozwala przekazywać dalej" do
      c = child("project.edit", "X/lang/pl", parent: "g3")

      assert {:error, :parent_not_delegable} =
               Authz.authorize_issue(c, "C", @founding, chain(), @now)
    end

    test "szersza akcja albo szerszy zasób to eskalacja" do
      assert {:error, :not_covered} =
               Authz.authorize_issue(
                 child("*", "X/lang/pl", parent: "g2"),
                 "B",
                 @founding,
                 chain(),
                 @now
               )

      assert {:error, :not_covered} =
               Authz.authorize_issue(
                 child("project.delete", "X/lang/pl", parent: "g2"),
                 "B",
                 @founding,
                 chain(),
                 @now
               )

      assert {:error, :not_covered} =
               Authz.authorize_issue(
                 child("project.edit", "X/readme", parent: "g2"),
                 "B",
                 @founding,
                 chain(),
                 @now
               )

      assert {:error, :not_covered} =
               Authz.authorize_issue(
                 child("project.edit", "X/*", parent: "g2"),
                 "B",
                 @founding,
                 chain(),
                 @now
               )
    end

    test "okno czasowe nie może wychodzić poza okno rodzica" do
      grants = chain(%{g2: [expires_at: @future]})

      assert :ok =
               Authz.authorize_issue(
                 child("project.edit", "X/lang/pl", parent: "g2", expires_at: @future),
                 "B",
                 @founding,
                 grants,
                 @now
               )

      assert {:error, :window_exceeds_parent} =
               Authz.authorize_issue(
                 child("project.edit", "X/lang/pl", parent: "g2"),
                 "B",
                 @founding,
                 grants,
                 @now
               )

      assert {:error, :window_exceeds_parent} =
               Authz.authorize_issue(
                 child("project.edit", "X/lang/pl",
                   parent: "g2",
                   expires_at: ~U[2100-01-01 00:00:00Z]
                 ),
                 "B",
                 @founding,
                 grants,
                 @now
               )
    end
  end

  describe "authorize_issue/5 — ważność łańcucha" do
    defp c, do: child("project.edit", "X/lang/pl", parent: "g2")

    test "wygasły grant nadrzędny" do
      assert {:error, {:grant_inactive, "g2"}} =
               Authz.authorize_issue(c(), "B", @founding, chain(%{g2: [expires_at: @past]}), @now)
    end

    test "grant nadrzędny jeszcze nieaktywny" do
      assert {:error, {:grant_inactive, "g2"}} =
               Authz.authorize_issue(
                 c(),
                 "B",
                 @founding,
                 chain(%{g2: [not_before: @future]}),
                 @now
               )
    end

    test "unieważnienie grantu nadrzędnego" do
      assert {:error, {:grant_inactive, "g2"}} =
               Authz.authorize_issue(c(), "B", @founding, chain(%{g2: [revoked_at: @past]}), @now)
    end

    test "unieważnienie przodka odcina całą dalszą część łańcucha" do
      grants = chain(%{g1: [revoked_at: @past]})

      assert {:error, {:grant_inactive, "g1"}} =
               Authz.authorize_issue(c(), "B", @founding, grants, @now)
    end

    test "wygaśnięcie przodka odcina całą dalszą część łańcucha" do
      grants = chain(%{g1: [expires_at: @past]})

      assert {:error, {:grant_inactive, "g1"}} =
               Authz.authorize_issue(c(), "B", @founding, grants, @now)
    end

    test "wystawca grantu nie jest podmiotem grantu nadrzędnego" do
      forged = [
        grant("g1", "F", "A", nil, delegable: true),
        grant("g2", "Z", "B", "g1", delegable: true)
      ]

      assert {:error, {:broken_chain, "g2"}} =
               Authz.authorize_issue(c(), "B", @founding, forged, @now)
    end

    test "grant korzenia wystawiony przez klucz inny niż założycielski" do
      forged = [grant("g2", "Z", "B", nil, delegable: true)]

      assert {:error, {:broken_chain, "g2"}} =
               Authz.authorize_issue(c(), "B", @founding, forged, @now)
    end

    test "rodzic bez delegable w środku łańcucha" do
      forged = [
        grant("g1", "F", "A", nil, delegable: false),
        grant("g2", "A", "B", "g1", delegable: true)
      ]

      assert {:error, {:broken_chain, "g2"}} =
               Authz.authorize_issue(c(), "B", @founding, forged, @now)
    end

    test "brakujące ogniwo" do
      broken = Enum.reject(chain(), &(&1.id == "g1"))

      assert {:error, {:broken_chain, "g2"}} =
               Authz.authorize_issue(c(), "B", @founding, broken, @now)
    end

    test "cykl nie zawiesza sprawdzania" do
      cyclic = [
        grant("g1", "B", "A", "g2", delegable: true),
        grant("g2", "A", "B", "g1", delegable: true)
      ]

      assert {:error, {:broken_chain, _}} =
               Authz.authorize_issue(c(), "B", @founding, cyclic, @now)
    end
  end

  describe "permits?/6" do
    test "klucz założycielski ma wszystko" do
      assert Authz.permits?([], @founding, "F", "cokolwiek", "X/dowolnie", @now)
    end

    test "uprawnienia wynikają z grantów i są węższe z każdym ogniwem" do
      grants = chain()

      assert Authz.permits?(grants, @founding, "A", "project.delete", "X/readme", @now)
      assert Authz.permits?(grants, @founding, "B", "project.edit", "X/lang/de", @now)
      refute Authz.permits?(grants, @founding, "B", "project.delete", "X/lang/de", @now)
      refute Authz.permits?(grants, @founding, "B", "project.edit", "X/readme", @now)
      assert Authz.permits?(grants, @founding, "C", "project.edit", "X/lang/pl", @now)
      refute Authz.permits?(grants, @founding, "C", "project.edit", "X/lang/de", @now)
    end

    test "nieznany klucz nic nie może" do
      refute Authz.permits?(chain(), @founding, "stranger", "project.edit", "X/lang/pl", @now)
    end

    test "unieważnienie lub wygaśnięcie ogniwa odbiera uprawnienia wszystkim niżej" do
      revoked = chain(%{g1: [revoked_at: @past]})

      for key <- ["A", "B", "C"],
          do:
            refute(
              Authz.permits?(revoked, @founding, key, "project.edit", "X/lang/pl", @now),
              key
            )

      expired_g2 = chain(%{g2: [expires_at: @past]})
      assert Authz.permits?(expired_g2, @founding, "A", "project.edit", "X/lang/pl", @now)
      refute Authz.permits?(expired_g2, @founding, "B", "project.edit", "X/lang/pl", @now)
      refute Authz.permits?(expired_g2, @founding, "C", "project.edit", "X/lang/pl", @now)
    end

    test "uprawnienie obowiązuje tylko w oknie czasowym" do
      grants = chain(%{g1: [not_before: ~U[2026-11-01 00:00:00Z]]})
      refute Authz.permits?(grants, @founding, "A", "project.edit", "X/y", @now)

      assert Authz.permits?(
               grants,
               @founding,
               "A",
               "project.edit",
               "X/y",
               ~U[2026-12-01 00:00:00Z]
             )
    end

    test "sfałszowany łańcuch nie daje uprawnień" do
      forged = [grant("g2", "Z", "B", nil, delegable: true)]
      refute Authz.permits?(forged, @founding, "B", "project.edit", "X/lang/pl", @now)
    end
  end
end
