Sequel.migration do
  change do
    alter_table :delayed_jobs do
      add_column :redactable_error, :string, null: true
    end
  end
end
