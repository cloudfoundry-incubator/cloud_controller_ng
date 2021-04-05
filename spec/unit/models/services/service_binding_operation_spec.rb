require 'spec_helper'
require 'support/shared_examples/models/operations'

module VCAP::CloudController
  RSpec.describe ServiceBindingOperation, type: :model do
    it_behaves_like 'operation'
  end
end
