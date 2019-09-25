module VCAP::CloudController
  class JobWarningModel < Sequel::Model(:job_warnings)
    many_to_one :job, class: 'VCAP::CloudController::PollableJobModel'

    import_attributes :warning, :job_guid
    export_attributes :job_guid, :warning
  end
end
