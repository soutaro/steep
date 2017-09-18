module Steep
  module Signature
    module Errors
      class Base
        # @implements Steep__Signature__Error

        # @dynamic signature
        attr_reader :signature

        def initialize(signature:)
          @signature = signature
        end
      end

      class UnknownTypeName < Base
        # @implements Steep__Signature__Errors__UnknownTypeName

        # @dynamic type
        attr_reader :type

        def initialize(signature:, type:)
          super(signature: signature)
          @type = type
        end

        def puts(io)
          io.puts "UnknownTypeName: signature=#{signature.name}, type=#{type}"
        end
      end

      class IncompatibleOverride < Base
        # @implements Steep__Signature__Errors__IncompatibleOverride

        # @dynamic method_name
        attr_reader :method_name
        # @dynamic this_method
        attr_reader :this_method
        # @dynamic super_method
        attr_reader :super_method

        def initialize(signature:, method_name:, this_method:, super_method:)
          super(signature: signature)
          @method_name = method_name
          @this_method = this_method
          @super_method = super_method
        end

        def puts(io)
          io.puts "IncompatibleOverride: signature=#{signature.name}, method=#{method_name}"
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

        def puts(io)
          io.puts "InvalidTypeApplication: signature=#{signature.name}, type_name=#{type_name}, type_args=#{type_args}"
        end
      end

      class InvalidSelfType < Base
        attr_reader :member

        def initialize(signature:, member:)
          super(signature: signature)
          @member = member
        end


        def puts(io)
          io.puts "InvalidSelfType: signature=#{signature.name}, module=#{member.name}"
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


        def puts(io)
          io.puts "UnexpectedTypeNameKind: signature=#{signature.name}, type=#{type}, kind=#{expected_kind}"
        end
      end
    end
  end
end

