Sequel.migration do
  change do
    create_table :external_service_bindings do
      VCAP::Migration.common(self, :external_service_bindings)

      Integer :service_binding_id
      String :credentials, size: 10000, null: false

      foreign_key :app_guid, :apps, :type=>String, :text=>true, :null=>false, :key=>[:guid]
    end
  end
end
