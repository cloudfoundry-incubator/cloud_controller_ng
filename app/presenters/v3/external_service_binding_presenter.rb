require 'presenters/v3/base_presenter'
require 'models/helpers/label_helpers'
require 'presenters/mixins/metadata_presentation_helpers'

module VCAP::CloudController
  module Presenters
    module V3
      class ExternalServiceBindingPresenter < BasePresenter
        def to_hash
          {
            platformName: external_service_binding.fetch(:platformName),
            serviceInstanceGuid: external_service_binding.fetch(:serviceInstanceGuid),
            credentials: external_service_binding.fetch(:credentials),
            links: build_links,
          }
        end

        private

        def external_service_binding
          @resource
        end

        def build_relationships
          if external_service_binding.space_guid.nil?
            {}
          else
            {
              space: {
                data: {
                  guid: external_service_binding.space_guid
                }
              }
            }
          end
        end

        def build_links
          url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

          { self:
            {
            href: url_builder.build_url(path: "/v3/external_service_bindings/#{external_service_binding.fetch(:guid)}")
            }
          }
        end
      end
    end
  end
end
