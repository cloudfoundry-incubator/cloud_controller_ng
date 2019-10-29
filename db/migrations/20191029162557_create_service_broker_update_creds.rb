Sequel.migration do
  change do
    create_table(:service_broker_update_creds) do
      VCAP::Migration.common(self)

      String :password, null: false
      String :salt, null: false
    end
  end
end
