module Steep
  module Signature
    module Errors
      class Base
        attr_reader :location

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

      class UnknownTypeNameError < Base
        attr_reader :name

        def initialize(name:, location:)
          @name = name
          @location = location
        end

        def puts(io)
          io.puts "#{loc_to_s}\tUnknownTypeNameError: name=#{name}"
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
          io.puts "#{loc_to_s}\tInvalidTypeApplicationError: name=#{name}, expected=[#{params.join(", ")}], actual=[#{args.join(", ")}]"
        end
      end
    end
  end
end

