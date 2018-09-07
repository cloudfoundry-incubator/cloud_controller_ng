require_relative 'api_presenter'

class JobPresenter < ApiPresenter
  def initialize(object, url_host_name=nil)
    super(object)
    @object ||= NullJob.new
    @url_host_name = url_host_name
  end

  protected

  def metadata_hash
    {
      guid: @object.guid,
      created_at: @object.created_at.iso8601,
      url: status_url
    }
  end

  def entity_hash
    entity_hash = {
      guid: @object.guid,
      status: status
    }

    if job_errored?
      entity_hash[:error] = error_deprecation_message
      entity_hash[:error_details] = error_details
    end

    entity_hash
  end

  private

  def status_url
    [@url_host_name, "v2/jobs/#{@object.guid}"].join('/')
  end

  def redact(redactable_error)
    template_values = {}
    redactable_error.template_parameters.each { |key, _| template_values[key] = 'REDACTED' }

    redactable_error.template_parameters.each do |template_key, redactable_element|
      obj = elem.object

      if VCAP::CloudController::Security::AccessContext.new.can?(:read, obj)
        template_values[template_key] = obj.send(elem.method)
      end
    end

    ERB.new(redactable_error.template).result_with_hash(template_values)
  end

  def error_details
    if @object.redactable_error
      redact(redactable_error)
    end
    YAML.safe_load(@object.cf_api_error, [Symbol])
  end

  def job_exception_or_nil
    if job_has_exception?
      VCAP::CloudController::ExceptionMarshaler.unmarshal(@object.cf_api_error)
    end
  end

  def job_has_exception?
    @object.cf_api_error || @object.redactable_error
  end

  def error_deprecation_message
    'Use of entity>error is deprecated in favor of entity>error_details.'
  end

  def status
    if job_errored?
      'failed'
    elsif job_missing?
      'finished'
    elsif job_queued?
      'queued'
    else
      'running'
    end
  end

  def job_queued?
    @object.locked_at.nil?
  end

  def job_missing?
    @object.is_a? NullJob
  end

  def job_errored?
    @object.cf_api_error || @object.redactable_error
  end

  class NullJob
    def id
      '0'
    end

    def guid
      '0'
    end

    def created_at
      Time.at(0).utc
    end

    def run_at
      Time.at(0).utc
    end

    def cf_api_error
      nil
    end

    def last_error
      nil
    end
  end
end
