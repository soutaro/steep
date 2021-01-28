module Steep
  module Diagnostic
    module Signature
      class Base
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def loc_to_s
          RBS::Location.to_string location
        end

        def to_s
          StringIO.new.tap do |io|
            puts io
          end.string
        end

        def path
          location.buffer.name
        end
      end

      class SyntaxError < Base
        attr_reader :exception

        def initialize(exception, location:)
          super(location: location)
          @exception = exception
        end

        def puts(io)
          io.puts "SyntaxError: #{exception.message}"
        end
      end

      class DuplicatedDeclarationError < Base
        attr_reader :type_name

        def initialize(type_name:, location:)
          @type_name = type_name
          @location = location
        end

        def puts(io)
          io.puts "DuplicatedDeclarationError: name=#{type_name}"
        end
      end

      class UnknownTypeNameError < Base
        attr_reader :name

        def initialize(name:, location:)
          @name = name
          @location = location
        end

        def puts(io)
          io.puts "UnknownTypeNameError: name=#{name}"
        end
      end

      class InvalidTypeApplicationError < Base
        attr_reader :name
        attr_reader :args
        attr_reader :params

        def initialize(name:, args:, params:, location:)
          @name = name
          @args = args
          @params = params
          @location = location
        end

        def puts(io)
          io.puts "InvalidTypeApplicationError: name=#{name}, expected=[#{params.join(", ")}], actual=[#{args.join(", ")}]"
        end
      end

      class InvalidMethodOverloadError < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          @class_name = class_name
          @method_name = method_name
          @location = location
        end

        def puts(io)
          io.puts "InvalidMethodOverloadError: class_name=#{class_name}, method_name=#{method_name}"
        end
      end

      class UnknownMethodAliasError < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          @class_name = class_name
          @method_name = method_name
          @location = location
        end

        def puts(io)
          io.puts "UnknownMethodAliasError: class_name=#{class_name}, method_name=#{method_name}"
        end
      end

      class DuplicatedMethodDefinitionError < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          @class_name = class_name
          @method_name = method_name
          @location = location
        end

        def puts(io)
          io.puts "DuplicatedMethodDefinitionError: class_name=#{class_name}, method_name=#{method_name}"
        end
      end

      class RecursiveAliasError < Base
        attr_reader :class_name
        attr_reader :names
        attr_reader :location

        def initialize(class_name:, names:, location:)
          @class_name = class_name
          @names = names
          @location = location
        end

        def puts(io)
          io.puts "RecursiveAliasError: class_name=#{class_name}, names=#{names.join(", ")}"
        end
      end
    end
  end
end
