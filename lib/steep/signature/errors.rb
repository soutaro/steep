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

    end
  end
end

