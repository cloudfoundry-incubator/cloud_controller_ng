module VCAP::CloudController
  module MessageNestedValidations
    def validates_nested(top_field, *fields, **opts)
      fields_identifier = "#{top_field}_#{fields.join('_')}"

      validate :"validate_#{fields_identifier}"

      define_method :"validate_#{fields_identifier}" do
        return unless send(top_field)

        unless send(top_field).is_a?(Hash)
          errors.add(top_field, 'must be of type hash')
          return
        end

        unless fields.empty?
          allowed = [fields[0]]
          allowed_representation = allowed.map(&:to_s).inspect
          extra_fields = send(top_field).keys.reject { |k| allowed.include?(k) }
          extra_fields_representation = extra_fields.map(&:to_s).inspect
          unless extra_fields.empty?
            errors.add(top_field, "must only contain fields #{allowed_representation}, but got #{extra_fields_representation}")
            return
          end
        end

        fields.each_with_index do |_, index|
          fields_prefix = fields[0..index]
          fields_prefix_representation = fields_prefix.join('.')
          expected = { type: Hash, representation: 'hash' }

          if index == fields.size - 1 && opts[:string]
            expected = { type: String, representation: 'string' }
          end

          unless send(top_field).dig(*fields_prefix).is_a?(expected[:type])
            errors.add(top_field, "#{fields_prefix_representation} must be of type #{expected[:representation]}")
            break
          end

          if fields.size > index + 1
            allowed = [fields[index + 1]]
            allowed_representation = allowed.map(&:to_s).inspect
            extra_fields = send(top_field).dig(*fields_prefix).keys.reject { |k| allowed.include?(k) }
            extra_fields_representation = extra_fields.map(&:to_s).inspect
            unless extra_fields.empty?
              errors.add(top_field, "#{fields_prefix_representation} must only contain fields #{allowed_representation}, but got #{extra_fields_representation}")
              break
            end
          end
        end
      end

      private :"validate_#{fields_identifier}"
    end
  end
end
