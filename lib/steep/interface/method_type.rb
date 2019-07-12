module Steep
  module Interface
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

      NONE = Object.new
      def update(required: NONE, optional: NONE, rest: NONE, required_keywords: NONE, optional_keywords: NONE, rest_keywords: NONE)
        self.class.new(
          required: required.equal?(NONE) ? self.required : required,
          optional: optional.equal?(NONE) ? self.optional : optional,
          rest: rest.equal?(NONE) ? self.rest : rest,
          required_keywords: required_keywords.equal?(NONE) ? self.required_keywords : required_keywords,
          optional_keywords: optional_keywords.equal?(NONE) ? self.optional_keywords : optional_keywords,
          rest_keywords: rest_keywords.equal?(NONE) ? self.rest_keywords : rest_keywords
        )
      end

      def self.empty
        self.new(
          required: [],
          optional: [],
          rest: nil,
          required_keywords: {},
          optional_keywords: {},
          rest_keywords: nil
        )
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

      def without_keywords
        self.class.new(
          required: required,
          optional: optional,
          rest: rest,
          required_keywords: {},
          optional_keywords: {},
          rest_keywords: nil
        )
      end

      def drop_first
        case
        when required.any? || optional.any? || rest
          self.class.new(
            required: required.any? ? required.drop(1) : [],
            optional: required.empty? && optional.any? ? optional.drop(1) : optional,
            rest: required.empty? && optional.empty? ? nil : rest,
            required_keywords: required_keywords,
            optional_keywords: optional_keywords,
            rest_keywords: rest_keywords
          )
        when has_keywords?
          without_keywords
        else
          raise "Cannot drop from empty params"
        end
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

      def each_type()
        if block_given?
          flat_unnamed_params.each do |(_, type)|
            yield type
          end
          flat_keywords.each do |_, type|
            yield type
          end
          rest and yield rest
          rest_keywords and yield rest_keywords
        else
          enum_for :each_type
        end
      end

      def free_variables
        Set.new.tap do |fvs|
          each_type do |type|
            fvs.merge type.free_variables
          end
        end
      end

      def closed?
        required.all?(&:closed?) && optional.all?(&:closed?) && (!rest || rest.closed?) && required_keywords.values.all?(&:closed?) && optional_keywords.values.all?(&:closed?) && (!rest_keywords || rest_keywords.closed?)
      end

      def subst(s)
        self.class.new(
          required: required.map {|t| t.subst(s) },
          optional: optional.map {|t| t.subst(s) },
          rest: rest&.subst(s),
          required_keywords: required_keywords.transform_values {|t| t.subst(s) },
          optional_keywords: optional_keywords.transform_values {|t| t.subst(s) },
          rest_keywords: rest_keywords&.subst(s)
        )
      end

      def size
        required.size + optional.size + (rest ? 1 : 0) + required_keywords.size + optional_keywords.size + (rest_keywords ? 1 : 0)
      end

      def to_s
        required = self.required.map {|ty| ty.to_s }
        optional = self.optional.map {|ty| "?#{ty}" }
        rest = self.rest ? ["*#{self.rest}"] : []
        required_keywords = self.required_keywords.map {|name, type| "#{name}: #{type}" }
        optional_keywords = self.optional_keywords.map {|name, type| "?#{name}: #{type}"}
        rest_keywords = self.rest_keywords ? ["**#{self.rest_keywords}"] : []
        "(#{(required + optional + rest + required_keywords + optional_keywords + rest_keywords).join(", ")})"
      end

      def map_type(&block)
        self.class.new(
          required: required.map(&block),
          optional: optional.map(&block),
          rest: rest && yield(rest),
          required_keywords: required_keywords.transform_values(&block),
          optional_keywords: optional_keywords.transform_values(&block),
          rest_keywords: rest_keywords && yield(rest_keywords)
        )
      end

      def empty?
        required.empty? && optional.empty? && !rest && !has_keywords?
      end
    end

    class Block
      attr_reader :type
      attr_reader :optional

      def initialize(type:, optional:)
        @type = type
        @optional = optional
      end

      def optional?
        @optional
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.optional == optional
      end

      def closed?
        type.closed?
      end

      def subst(s)
        self.class.new(
          type: type.subst(s),
          optional: optional
        )
      end

      def free_variables
        type.free_variables
      end

      def to_s
        "#{optional? ? "?" : ""}{ #{type.params} -> #{type.return_type} }"
      end

      def map_type(&block)
        self.class.new(
          type: type.map_type(&block),
          optional: optional
        )
      end
    end

    class MethodType
      attr_reader :type_params
      attr_reader :params
      attr_reader :block
      attr_reader :return_type
      attr_reader :location

      NONE = Object.new

      def initialize(type_params:, params:, block:, return_type:, location:)
        @type_params = type_params
        @params = params
        @block = block
        @return_type = return_type
        @location = location
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.type_params == type_params &&
          other.params == params &&
          other.block == block &&
          other.return_type == return_type &&
          (!other.location || !location || other.location == location)
      end

      def free_variables
        (params.free_variables + (block&.free_variables || Set.new) + return_type.free_variables) - Set.new(type_params)
      end

      def subst(s)
        s_ = s.except(type_params)

        self.class.new(
          type_params: type_params,
          params: params.subst(s_),
          block: block&.subst(s_),
          return_type: return_type.subst(s_),
          location: location
        )
      end

      def each_type(&block)
        if block_given?
          params.each_type(&block)
          self.block&.tap do
            self.block.type.params.each_type(&block)
            yield(self.block.type.return_type)
          end
          yield(return_type)
        else
          enum_for :each_type
        end
      end

      def instantiate(s)
        self.class.new(
          type_params: [],
          params: params.subst(s),
          block: block&.subst(s),
          return_type: return_type.subst(s),
          location: location,
          )
      end

      def with(type_params: NONE, params: NONE, block: NONE, return_type: NONE, location: NONE)
        self.class.new(
          type_params: type_params.equal?(NONE) ? self.type_params : type_params,
          params: params.equal?(NONE) ? self.params : params,
          block: block.equal?(NONE) ? self.block : block,
          return_type: return_type.equal?(NONE) ? self.return_type : return_type,
          location: location.equal?(NONE) ? self.location : location
        )
      end

      def to_s
        type_params = !self.type_params.empty? ? "<#{self.type_params.map{|x| "'#{x}" }.join(", ")}> " : ""
        params = self.params.to_s
        block = self.block ? " #{self.block}" : ""

        "#{type_params}#{params}#{block} -> #{return_type}"
      end

      def map_type(&block)
        self.class.new(
          type_params: type_params,
          params: params.map_type(&block),
          block: self.block&.yield_self {|blk| blk.map_type(&block) },
          return_type: yield(return_type),
          location: location
        )
      end
    end
  end
end
