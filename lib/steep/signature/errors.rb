module Steep
  module Signature
    module Errors
      class Base
        attr_reader :signature

        def initialize(signature:)
          @signature = signature
        end
      end

      class UnknownTypeName < Base
        attr_reader :type

        def initialize(signature:, type:)
          super(signature: signature)
          @type = type
        end
      end

      class IncompatibleOverride < Base
        attr_reader :this_method
        attr_reader :super_method

        def initialize(signature:, this_method:, super_method:)
          super(signature: signature)
          @this_method = this_method
          @super_method = super_method
        end
      end

      class InvalidTypeApplication < Base
        attr_reader :type_name
        attr_reader :type_args

        def initialize(signature:, type_name:, type_args:)
          super(signature: signature)
          @type_name = type_name
          @type_args = type_args
        end
      end

      class InvalidSelfType < Base
        attr_reader :type

        def initialize(signature:, type:)
          super(signature: signature)
          @type = type
        end
      end

      class UnexpectedTypeNameKind < Base
        attr_reader :type
        attr_reader :expected_kind

        def initialize(signature:, type:, expected_kind:)
          super(signature: signature)
          @type = type
          @expected_kind = expected_kind
        end
      end
    end
  end
end

