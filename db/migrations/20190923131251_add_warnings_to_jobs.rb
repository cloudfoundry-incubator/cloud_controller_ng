Sequel.migration do
  change do
    add_column :jobs, :warnings, String, size: 16_000, null: true
  end
end
