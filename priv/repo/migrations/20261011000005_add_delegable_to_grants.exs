defmodule Oktavarium.Repo.Migrations.AddDelegableToGrants do
  use Ecto.Migration

  def change do
    alter table(:grants) do
      # czy posiadacz może na podstawie tego grantu wystawiać dalsze granty
      add :delegable, :boolean, null: false, default: false
    end
  end
end
