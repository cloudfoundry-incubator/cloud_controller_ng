require 'spec_helper'
require 'support/link_helpers'
require 'presenters/v3/service_offering_presenter'

RSpec.describe VCAP::CloudController::Presenters::V3::ServiceOfferingPresenter do
  let(:guid) { 'some-offering-guid' }
  let(:name) { 'some-offering-name' }
  let(:description) { 'some offering description' }
  let(:available) { true }
  let(:bindable) { true }
  let(:metatdata) { '{"foo" => "bar"}' }
  let(:id) { 'broker-id' }
  let(:tags) { %w(foo bar) }
  let(:requires) { %w(syslog_drain route_forwarding volume_mount) }
  let(:updatable) { true }
  let(:model) do
    VCAP::CloudController::Service.make(
      guid: guid,
      label: name,
      description: description,
      active: available,
      bindable: bindable,
      extra: metatdata,
      unique_id: id,
      tags: tags,
      requires: requires,
      plan_updateable: updatable
    )
  end

  describe '#to_hash' do
    let(:result) { described_class.new(model).to_hash }

    it 'presents the service offering as JSON' do
      expect(result).to eq({
        'guid': guid,
        'name': name,
        'description': description,
        'available': available,
        'bindable': bindable,
        'broker_service_offering_metadata': metatdata,
        'broker_service_offering_id': id,
        'tags': tags,
        'requires': requires,
        'created_at': model.created_at,
        'updated_at': model.updated_at,
        'plan_updateable': updatable
      })
    end
  end
end
