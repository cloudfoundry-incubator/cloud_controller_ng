module VCAP::CloudController
  SPACE_OR_ORGANIZATION_NOT_SPECIFIED = -1

  # Sequel allows to create models based on datasets. The following is a dataset that unions all the individual roles
  # tables and labels each row with a `type` column based on which table it came from
  class Role < Sequel::Model(
    OrganizationUser.select(
      Sequel.as(VCAP::CloudController::RoleTypes::ORGANIZATION_USER, :type),
      Sequel.as(:role_guid, :guid),
      :user_id,
      :organization_id,
      Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :space_id),
      :created_at,
      :updated_at
    ).union(
      OrganizationManager.select(
        Sequel.as(VCAP::CloudController::RoleTypes::ORGANIZATION_MANAGER, :type),
        Sequel.as(:role_guid, :guid),
        :user_id,
        :organization_id,
        Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :space_id),
        :created_at,
        :updated_at)
    ).union(
      OrganizationBillingManager.select(
        Sequel.as(VCAP::CloudController::RoleTypes::ORGANIZATION_BILLING_MANAGER, :type),
        Sequel.as(:role_guid, :guid),
        :user_id,
        :organization_id,
        Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :space_id),
        :created_at,
        :updated_at)
    ).union(
      OrganizationAuditor.select(
        Sequel.as(VCAP::CloudController::RoleTypes::ORGANIZATION_AUDITOR, :type),
        Sequel.as(:role_guid, :guid),
        :user_id,
        :organization_id,
        Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :space_id),
        :created_at,
        :updated_at)
    ).union(
      SpaceDeveloper.select(
        Sequel.as(VCAP::CloudController::RoleTypes::SPACE_DEVELOPER, :type),
        Sequel.as(:role_guid, :guid),
        :user_id,
        Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :organization_id),
        :space_id,
        :created_at,
        :updated_at)
    ).union(
      SpaceAuditor.select(
        Sequel.as(VCAP::CloudController::RoleTypes::SPACE_AUDITOR, :type),
        Sequel.as(:role_guid, :guid),
        :user_id,
        Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :organization_id),
        :space_id,
        :created_at,
        :updated_at)
    ).union(
      SpaceManager.select(
        Sequel.as(VCAP::CloudController::RoleTypes::SPACE_MANAGER, :type),
        Sequel.as(:role_guid, :guid),
        :user_id,
        Sequel.as(SPACE_OR_ORGANIZATION_NOT_SPECIFIED, :organization_id),
        :space_id,
        :created_at,
        :updated_at))
  )

    def user_guid
      User.first(id: user_id).guid
    end

    def organization_guid
      Organization.first(id: organization_id).guid
    end

    def space_guid
      Space.first(id: space_id).guid
    end
  end
end
