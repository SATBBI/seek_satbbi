module Seek
  module Samples
    module AttributeTypeHandlers
      class CVListAttributeTypeHandler < CVAttributeTypeHandler

        def test_value(array_value)
            array_value.each do |value|
              fail "'#{value}' is not included in the controlled vocabulary" unless controlled_vocab.includes_term?(value) || controlled_vocab.custom_input
            end
        end


        def convert(value)
          return value if value.is_a?(Array)
          value.split(',').collect{|v| v.strip}
        end

      end
    end
  end
end
