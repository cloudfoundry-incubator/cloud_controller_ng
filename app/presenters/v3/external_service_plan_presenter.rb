require 'presenters/v3/base_presenter'
require 'models/helpers/label_helpers'
require 'presenters/mixins/metadata_presentation_helpers'

module VCAP::CloudController
  module Presenters
    module V3
      class ExternalServicePlanPresenter < BasePresenter
        def to_hash
          {
            guid: external_service_plan.guid,
            name: external_service_plan.name,
            description: external_service_plan.description,
            created_at: external_service_plan.created_at,
            updated_at: external_service_plan.updated_at,
            links: build_links,
          }
        end

        private

        def external_service_plan
          @resource
        end

        def build_relationships
          if external_service_plan.space_guid.nil?
            {}
          else
            {
              space: {
                data: {
                  guid: external_service_plan.space_guid
                }
              }
            }
          end
        end

        def build_links
          url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

          { self:
            {
              href: url_builder.build_url(path: "/v3/external_service_plans/#{external_service_plan.guid}")
            }
          }
        end
      end
    end
  end
end
