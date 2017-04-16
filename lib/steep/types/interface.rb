module Steep
  module Types
    class Interface
      class Params
        attr_reader :required
        attr_reader :optional
        attr_reader :rest
        attr_reader :required_keywords
        attr_reader :optional_keywords
        attr_reader :rest_keywords

        def initialize(required:, optional:, rest:, required_keywords:, optional_keywords:, rest_keywords:)
          @required = required
          @optional = optional
          @rest = rest
          @required_keywords = required_keywords
          @optional_keywords = optional_keywords
          @rest_keywords = rest_keywords
        end

        def with(required: nil, optional: nil, rest: nil, required_keywords: nil, optional_keywords: nil, rest_keywords: nil)
          self.class.new(required: required || self.required,
                         optional: optional || self.optional,
                         rest: rest || self.rest,
                         required_keywords: required_keywords || self.required_keywords,
                         optional_keywords: optional_keywords || self.optional_keywords,
                         rest_keywords: rest_keywords || self.rest_keywords)
        end

        def self.empty
          new(required: [], optional: [], rest: nil, required_keywords: {}, optional_keywords: {}, rest_keywords: nil)
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.required == required &&
            other.optional == optional &&
            other.rest == rest &&
            other.required_keywords == required_keywords &&
            other.optional_keywords == optional_keywords &&
            other.rest_keywords == rest_keywords
        end

        def flat_unnamed_params
          required.map {|p| [:required, p] } + optional.map {|p| [:optional, p] }
        end

        def flat_keywords
          required_keywords.merge optional_keywords
        end

        def has_keywords?
          !required_keywords.empty? || !optional_keywords.empty? || rest_keywords
        end

        def each_missing_argument(args)
          required.size.times do |index|
            if index >= args.size
              yield index
            end
          end
        end

        def each_extra_argument(args)
          return if rest

          if has_keywords?
            args = args.take(args.count - 1) if args.count > 0
          end

          args.size.times do |index|
            if index >= required.count + optional.count
              yield index
            end
          end
        end

        def each_missing_keyword(args)
          return unless has_keywords?

          keywords, rest = extract_keywords(args)

          return unless rest.empty?

          required_keywords.each do |keyword, _|
            yield keyword unless keywords.key?(keyword)
          end
        end

        def each_extra_keyword(args)
          return unless has_keywords?
          return if rest_keywords

          keywords, rest = extract_keywords(args)

          return unless rest.empty?

          all_keywords = flat_keywords
          keywords.each do |keyword, _|
            yield keyword unless all_keywords.key?(keyword)
          end
        end

        def extract_keywords(args)
          last_arg = args.last

          keywords = {}
          rest = []

          if last_arg&.type == :hash
            last_arg.children.each do |element|
              case element.type
              when :pair
                if element.children[0].type == :sym
                  name = element.children[0].children[0]
                  keywords[name] = element.children[1]
                end
              when :kwsplat
                rest << element.children[0]
              end
            end
          end

          [keywords, rest]
        end
      end

      class Method
        attr_reader :params
        attr_reader :block
        attr_reader :return_type

        def initialize(params:, block:, return_type:)
          @params = params
          @block = block
          @return_type = return_type
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.params == params &&
            other.block == block &&
            other.return_type == return_type
        end
      end

      class Block
        attr_reader :params
        attr_reader :return_type

        def initialize(params:, return_type:)
          @params = params
          @return_type = return_type
        end

        def ==(other)
          other.is_a?(self.class) && other.params == params && other.return_type == return_type
        end
      end

      attr_reader :name
      attr_reader :methods

      def initialize(name:, methods:)
        @name = name
        @methods = methods
      end

      def ==(other)
        other.is_a?(self.class) && other.name == name && other.methods == methods
      end
    end
  end
end
