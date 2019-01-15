require 'presenters/v3/base_presenter'
require 'models/helpers/label_helpers'
require 'presenters/mixins/metadata_presentation_helpers'

module VCAP::CloudController
  module Presenters
    module V3
      class ExternalServiceInstancePresenter < BasePresenter
        def to_hash
          {
            name: external_service_instance.fetch(:name),
            plan_id: external_service_instance.fetch(:plan_id),
            service_id: external_service_instance.fetch(:service_id),
            guid: external_service_instance.fetch(:guid, ''),
            links: build_links,
          }
        end

        private

        def external_service_instance
          @resource
        end

        def build_relationships
          if external_service_instance.space_guid.nil?
            {}
          else
            {
              space: {
                data: {
                  guid: external_service_instance.space_guid
                }
              }
            }
          end
        end

        def build_links
          url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

          { self:
            {
            href: url_builder.build_url(path: "/v3/external_service_instances/#{external_service_instance.fetch(:guid)}")
            }
          }
        end
      end
    end
  end
end
