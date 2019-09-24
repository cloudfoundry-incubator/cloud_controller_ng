module VCAP::CloudController
  class PollableJobModel < Sequel::Model(:jobs)
    PROCESSING_STATE = 'PROCESSING'.freeze
    COMPLETE_STATE   = 'COMPLETE'.freeze
    FAILED_STATE     = 'FAILED'.freeze

    plugin :serialization
    serialize_attributes :yaml, :warnings

    def validate
      validates_type [Array, NilClass], :warnings, Sequel::Plugins::ValidationHelpers::DEFAULT_OPTIONS[:type]
      validates_warning_items
    end

    def complete?
      state == VCAP::CloudController::PollableJobModel::COMPLETE_STATE
    end

    def resource_exists?
      !!Sequel::Model(ActiveSupport::Inflector.pluralize(resource_type).to_sym).find(guid: resource_guid)
    end

    def self.find_by_delayed_job(delayed_job)
      find_by_delayed_job_guid(delayed_job.guid)
    end

    def self.find_by_delayed_job_guid(delayed_job_guid)
      pollable_job = PollableJobModel.find(delayed_job_guid: delayed_job_guid)

      raise "No pollable job found for delayed_job '#{delayed_job_guid}'" if pollable_job.nil?

      pollable_job
    end

    private

    def validates_warning_items
      if warnings.is_a?(Array)
        warnings.each do |item|
          unless item.is_a?(Hash) && (item.key?(:message) || item.key?('message'))
            errors.add(:warnings, "should contain only hashes with a :message key, but found '#{item.inspect}'")
            next
          end

          message = item.fetch(:message, item['message'])
          unless message.is_a?(String)
            errors.add(:'warnings[].message', "should be a string, but found '#{message}'")
          end
        end
      end
    end
  end
end
