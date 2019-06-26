RSpec.shared_examples_for 'invalid nested message type' do |top_field, *nested_fields, type:|
  let(:request_body) { raise 'Please provide let(:request_body)' }

  fields = nested_fields.join('.')
  full_fields = fields.empty? ? top_field : "#{top_field}.#{fields}"

  context "when #{full_fields} is not of type #{type}" do
    it 'is not valid' do
      message = subject.new(request_body)

      expect(message).not_to be_valid

      expected_error = "#{fields} must be of type #{type}".strip
      actual = message.errors_on(top_field)
      expect(actual).to include(expected_error), %{
        expected errors on #{top_field.inspect} to include error #{expected_error.inspect}

        Expected: #{expected_error.inspect}
        Actual:   #{actual.inspect}
      }
    end
  end
end

RSpec.shared_examples_for 'invalid nested message extra' do |top_field, *nested_fields, extra:, allowed:|
  let(:request_body) { raise 'Please provide let(:request_body)' }

  fields = nested_fields.join('.')
  full_fields = fields.empty? ? top_field : "#{top_field}.#{fields}"

  allowed = allowed.map(&:to_s)
  extra = extra.map(&:to_s)

  context "when #{full_fields} has invalid extra field" do
    it 'is not valid' do
      message = subject.new(request_body)

      expect(message).not_to be_valid

      expected_error = "#{fields} must only contain fields #{allowed.inspect}, but got #{extra.inspect}".strip
      actual = message.errors_on(top_field)
      expect(actual).to include(expected_error), %{
        expected errors on #{top_field.inspect} to include error #{expected_error.inspect}

        Expected: #{expected_error.inspect}
        Actual:   #{actual.inspect}
      }
    end
  end
end

RSpec.shared_examples_for 'valid nested message' do |top_field|
  let(:request_body) { raise 'Please provide let(:request_body)' }

  context "when #{top_field} is valid" do
    it 'does not have any errors' do
      message = subject.new(request_body)

      expect(message).to be_valid
      expect(message.errors_on(top_field)).to be_empty
    end
  end
end
