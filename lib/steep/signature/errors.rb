module Steep
  module Signature
    module Errors
      class Base
        attr_reader :location

        def loc_to_s
          Ruby::Signature::Location.to_string location
        end

        def to_s
          StringIO.new.tap do |io|
            puts io
          end.string
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

      class NoSubtypingInheritanceError < Base
        attr_reader :type
        attr_reader :super_type
        attr_reader :error
        attr_reader :trace

        def initialize(type:, super_type:, error:, trace:, location:)
          @type = type
          @super_type = super_type
          @error = error
          @trace = trace
          @location = location
        end

        def puts(io)
          io.puts "#{loc_to_s}\tNoSubtypingInheritanceError: expected subtyping relation: #{type} <: #{super_type}"
          trace.each.with_index do |t, i|
            prefix = " " * i
            case t[0]
            when :type
              io.puts "#{prefix}#{t[1]} <: #{t[2]}"
            when :method
              io.puts "#{prefix}(#{t[3]}) #{t[1]} <: #{t[2]}"
            when :method_type
              io.puts "#{prefix}#{t[1]} <: #{t[2]}"
            end
          end
        end
      end
    end
  end
end

