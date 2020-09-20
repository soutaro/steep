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

      def update(required: self.required, optional: self.optional, rest: self.rest, required_keywords: self.required_keywords, optional_keywords: self.optional_keywords, rest_keywords: self.rest_keywords)
        self.class.new(
          required: required,
          optional: optional,
          rest: rest,
          required_keywords: required_keywords,
          optional_keywords: optional_keywords,
          rest_keywords: rest_keywords,
        )
      end

      RequiredPositional = Struct.new(:type)
      OptionalPositional = Struct.new(:type)
      RestPositional = Struct.new(:type)

      def first_param
        case
        when !required.empty?
          RequiredPositional.new(required[0])
        when !optional.empty?
          OptionalPositional.new(optional[0])
        when rest
          RestPositional.new(rest)
        else
          nil
        end
      end

      def with_first_param(param)
        case param
        when RequiredPositional
          update(required: [param.type] + required)
        when OptionalPositional
          update(optional: [param.type] + required)
        when RestPositional
          update(rest: param.type)
        else
          self
        end
      end

      def has_positional?
        first_param
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

      alias eql? ==

      def hash
        required.hash ^ optional.hash ^ rest.hash ^ required_keywords.hash ^ optional_keywords.hash ^ rest_keywords.hash
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

      def free_variables()
        @fvs ||= Set.new.tap do |set|
          each_type do |type|
            set.merge(type.free_variables)
          end
        end
      end

      def closed?
        required.all?(&:closed?) && optional.all?(&:closed?) && (!rest || rest.closed?) && required_keywords.values.all?(&:closed?) && optional_keywords.values.all?(&:closed?) && (!rest_keywords || rest_keywords.closed?)
      end

      def subst(s)
        return self if s.empty?
        return self if empty?
        return self if free_variables.disjoint?(s.domain)

        rs = required.map {|t| t.subst(s) }
        os = optional.map {|t| t.subst(s) }
        r = rest&.subst(s)
        rk = required_keywords.transform_values {|t| t.subst(s) }
        ok = optional_keywords.transform_values {|t| t.subst(s) }
        k = rest_keywords&.subst(s)

        if rs == required && os == optional && r == rest && rk == required_keywords && ok == optional_keywords && k == rest_keywords
          self
        else
          self.class.new(
            required: required.map {|t| t.subst(s) },
            optional: optional.map {|t| t.subst(s) },
            rest: rest&.subst(s),
            required_keywords: required_keywords.transform_values {|t| t.subst(s) },
            optional_keywords: optional_keywords.transform_values {|t| t.subst(s) },
            rest_keywords: rest_keywords&.subst(s)
          )
        end
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
        !has_positional? && !has_keywords?
      end

      # self + params returns a new params for overloading.
      #
      def +(other)
        a = first_param
        b = other.first_param

        case
        when a.is_a?(RequiredPositional) && b.is_a?(RequiredPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other.drop_first).with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.is_a?(OptionalPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other.drop_first).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.is_a?(RestPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.nil?
          (self.drop_first + other).with_first_param(OptionalPositional.new(a.type))
        when a.is_a?(OptionalPositional) && b.is_a?(RequiredPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other.drop_first).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.is_a?(OptionalPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other.drop_first).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.is_a?(RestPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.nil?
          (self.drop_first + other).with_first_param(OptionalPositional.new(a.type))
        when a.is_a?(RestPositional) && b.is_a?(RequiredPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self + other.drop_first).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.is_a?(OptionalPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self + other.drop_first).with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.is_a?(RestPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first + other.drop_first).with_first_param(RestPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.nil?
          (self.drop_first + other).with_first_param(RestPositional.new(a.type))
        when a.nil? && b.is_a?(RequiredPositional)
          (self + other.drop_first).with_first_param(OptionalPositional.new(b.type))
        when a.nil? && b.is_a?(OptionalPositional)
          (self + other.drop_first).with_first_param(OptionalPositional.new(b.type))
        when a.nil? && b.is_a?(RestPositional)
          (self + other.drop_first).with_first_param(RestPositional.new(b.type))
        when a.nil? && b.nil?
          required_keywords = {}

          (Set.new(self.required_keywords.keys) & Set.new(other.required_keywords.keys)).each do |keyword|
            required_keywords[keyword] = AST::Types::Union.build(
              types: [
                self.required_keywords[keyword],
                other.required_keywords[keyword]
              ]
            )
          end

          optional_keywords = {}
          self.required_keywords.each do |keyword, t|
            unless required_keywords.key?(keyword)
              case
              when other.optional_keywords.key?(keyword)
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, other.optional_keywords[keyword]])
              when other.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, other.rest_keywords])
              else
                optional_keywords[keyword] = t
              end
            end
          end
          other.required_keywords.each do |keyword, t|
            unless required_keywords.key?(keyword)
              case
              when self.optional_keywords.key?(keyword)
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, self.optional_keywords[keyword]])
              when self.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, self.rest_keywords])
              else
                optional_keywords[keyword] = t
              end
            end
          end
          self.optional_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword)
              case
              when other.optional_keywords.key?(keyword)
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, other.optional_keywords[keyword]])
              when other.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, other.rest_keywords])
              else
                optional_keywords[keyword] = t
              end
            end
          end
          other.optional_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword)
              case
              when self.optional_keywords.key?(keyword)
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, self.optional_keywords[keyword]])
              when self.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, self.rest_keywords])
              else
                optional_keywords[keyword] = t
              end
            end
          end

          rest = case
                 when self.rest_keywords && other.rest_keywords
                   AST::Types::Union.build(types: [self.rest_keywords, other.rest_keywords])
                 else
                   self.rest_keywords || other.rest_keywords
                 end

          Params.new(
                  required: [],
                  optional: [],
                  rest: nil,
                  required_keywords: required_keywords,
                  optional_keywords: optional_keywords,
                  rest_keywords: rest)
        end
      end

      # Returns the intersection between self and other.
      # Returns nil if the intersection cannot be computed.
      #
      def &(other)
        a = first_param
        b = other.first_param

        case
        when a.is_a?(RequiredPositional) && b.is_a?(RequiredPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other.drop_first)&.with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.is_a?(OptionalPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other.drop_first)&.with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.is_a?(RestPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other)&.with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.nil?
          nil
        when a.is_a?(OptionalPositional) && b.is_a?(RequiredPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other.drop_first)&.with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.is_a?(OptionalPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.is_a?(RestPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.nil?
          self.drop_first & other
        when a.is_a?(RestPositional) && b.is_a?(RequiredPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self & other.drop_first)&.with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.is_a?(OptionalPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self & other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.is_a?(RestPositional)
          AST::Types::Intersection.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first & other.drop_first)&.with_first_param(RestPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.nil?
          self.drop_first & other
        when a.nil? && b.is_a?(RequiredPositional)
          nil
        when a.nil? && b.is_a?(OptionalPositional)
          self & other.drop_first
        when a.nil? && b.is_a?(RestPositional)
          self & other.drop_first
        when a.nil? && b.nil?
          optional_keywords = {}

          (Set.new(self.optional_keywords.keys) & Set.new(other.optional_keywords.keys)).each do |keyword|
            optional_keywords[keyword] = AST::Types::Intersection.build(
              types: [
                self.optional_keywords[keyword],
                other.optional_keywords[keyword]
              ]
            )
          end

          required_keywords = {}
          self.optional_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword)
              case
              when other.required_keywords.key?(keyword)
                required_keywords[keyword] = AST::Types::Intersection.build(types: [t, other.required_keywords[keyword]])
              when other.rest_keywords
                optional_keywords[keyword] = AST::Types::Intersection.build(types: [t, other.rest_keywords])
              end
            end
          end
          other.optional_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword)
              case
              when self.required_keywords.key?(keyword)
                required_keywords[keyword] = AST::Types::Intersection.build(types: [t, self.required_keywords[keyword]])
              when self.rest_keywords
                optional_keywords[keyword] = AST::Types::Intersection.build(types: [t, self.rest_keywords])
              end
            end
          end
          self.required_keywords.each do |keyword, t|
            unless required_keywords.key?(keyword)
              case
              when other.required_keywords.key?(keyword)
                required_keywords[keyword] = AST::Types::Intersection.build(types: [t, other.required_keywords[keyword]])
              when other.rest_keywords
                required_keywords[keyword] = AST::Types::Intersection.build(types: [t, other.rest_keywords])
              else
                return
              end
            end
          end
          other.required_keywords.each do |keyword, t|
            unless required_keywords.key?(keyword)
              case
              when self.required_keywords.key?(keyword)
                required_keywords[keyword] = AST::Types::Intersection.build(types: [t, self.required_keywords[keyword]])
              when self.rest_keywords
                required_keywords[keyword] = AST::Types::Intersection.build(types: [t, self.rest_keywords])
              else
                return
              end
            end
          end

          rest = case
                 when self.rest_keywords && other.rest_keywords
                   AST::Types::Intersection.build(types: [self.rest_keywords, other.rest_keywords])
                 else
                   nil
                 end

          Params.new(
            required: [],
            optional: [],
            rest: nil,
            required_keywords: required_keywords,
            optional_keywords: optional_keywords,
            rest_keywords: rest)
        end
      end

      # Returns the union between self and other.
      #
      def |(other)
        a = first_param
        b = other.first_param

        case
        when a.is_a?(RequiredPositional) && b.is_a?(RequiredPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(RequiredPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.is_a?(OptionalPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.is_a?(RestPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RequiredPositional) && b.nil?
          self.drop_first&.with_first_param(OptionalPositional.new(a.type))
        when a.is_a?(OptionalPositional) && b.is_a?(RequiredPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.is_a?(OptionalPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.is_a?(RestPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(OptionalPositional) && b.nil?
          (self.drop_first | other)&.with_first_param(a)
        when a.is_a?(RestPositional) && b.is_a?(RequiredPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.is_a?(OptionalPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self | other.drop_first)&.with_first_param(OptionalPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.is_a?(RestPositional)
          AST::Types::Union.build(types: [a.type, b.type]).yield_self do |type|
            (self.drop_first | other.drop_first)&.with_first_param(RestPositional.new(type))
          end
        when a.is_a?(RestPositional) && b.nil?
          (self.drop_first | other)&.with_first_param(a)
        when a.nil? && b.is_a?(RequiredPositional)
          other.drop_first&.with_first_param(OptionalPositional.new(b.type))
        when a.nil? && b.is_a?(OptionalPositional)
          (self | other.drop_first)&.with_first_param(b)
        when a.nil? && b.is_a?(RestPositional)
          (self | other.drop_first)&.with_first_param(b)
        when a.nil? && b.nil?
          required_keywords = {}
          optional_keywords = {}

          (Set.new(self.required_keywords.keys) & Set.new(other.required_keywords.keys)).each do |keyword|
            required_keywords[keyword] = AST::Types::Union.build(
              types: [
                self.required_keywords[keyword],
                other.required_keywords[keyword]
              ]
            )
          end

          self.optional_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword) || required_keywords.key?(keyword)
              case
              when s = other.required_keywords[keyword]
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, s])
              when s = other.optional_keywords[keyword]
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, s])
              when r = other.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, r])
              else
                optional_keywords[keyword] = t
              end
            end
          end
          other.optional_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword) || required_keywords.key?(keyword)
              case
              when s = self.required_keywords[keyword]
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, s])
              when s = self.optional_keywords[keyword]
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, s])
              when r = self.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, r])
              else
                optional_keywords[keyword] = t
              end
            end
          end
          self.required_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword) || required_keywords.key?(keyword)
              case
              when s = other.optional_keywords[keyword]
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, s])
              when r = other.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, r])
              else
                optional_keywords[keyword] = t
              end
            end
          end
          other.required_keywords.each do |keyword, t|
            unless optional_keywords.key?(keyword) || required_keywords.key?(keyword)
              case
              when s = self.optional_keywords[keyword]
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, s])
              when r = self.rest_keywords
                optional_keywords[keyword] = AST::Types::Union.build(types: [t, r])
              else
                optional_keywords[keyword] = t
              end
            end
          end

          rest = case
                 when self.rest_keywords && other.rest_keywords
                   AST::Types::Union.build(types: [self.rest_keywords, other.rest_keywords])
                 when self.rest_keywords
                   if required_keywords.empty? && optional_keywords.empty?
                     self.rest_keywords
                   end
                 when other.rest_keywords
                   if required_keywords.empty? && optional_keywords.empty?
                     other.rest_keywords
                   end
                 else
                   nil
                 end

          Params.new(
            required: [],
            optional: [],
            rest: nil,
            required_keywords: required_keywords,
            optional_keywords: optional_keywords,
            rest_keywords: rest)
        end
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

      def to_optional
        self.class.new(
          type: type,
          optional: true
        )
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.optional == optional
      end

      alias eql? ==

      def hash
        type.hash ^ optional.hash
      end

      def closed?
        type.closed?
      end

      def subst(s)
        ty = type.subst(s)
        if ty == type
          self
        else
          self.class.new(
            type: ty,
            optional: optional
          )
        end
      end

      def free_variables()
        @fvs ||= type.free_variables
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

      def +(other)
        optional = self.optional? || other.optional?
        type = AST::Types::Proc.new(
          params: self.type.params + other.type.params,
          return_type: AST::Types::Union.build(types: [self.type.return_type, other.type.return_type])
        )
        self.class.new(
          type: type,
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
      attr_reader :method_def

      def initialize(type_params:, params:, block:, return_type:, location:, method_def:)
        @type_params = type_params
        @params = params
        @block = block
        @return_type = return_type
        @location = location
        @method_def = method_def
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.type_params == type_params &&
          other.params == params &&
          other.block == block &&
          other.return_type == return_type &&
          (!other.method_def || !method_def || other.method_def == method_def) &&
          (!other.location || !location || other.location == location)
      end

      alias eql? ==

      def hash
        type_params.hash ^ params.hash ^ block.hash ^ return_type.hash
      end

      def free_variables
        @fvs ||= Set.new.tap do |set|
          set.merge(params.free_variables)
          if block
            set.merge(block.free_variables)
          end
          set.merge(return_type.free_variables)
          set.subtract(type_params)
        end
      end

      def subst(s)
        return self if s.empty?
        return self if free_variables.disjoint?(s.domain)

        s_ = s.except(type_params)

        self.class.new(
          type_params: type_params,
          params: params.subst(s_),
          block: block&.subst(s_),
          return_type: return_type.subst(s_),
          method_def: method_def,
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
        self.class.new(type_params: [],
                       params: params.subst(s),
                       block: block&.subst(s),
                       return_type: return_type.subst(s),
                       location: location,
                       method_def: method_def)
      end

      def with(type_params: self.type_params, params: self.params, block: self.block, return_type: self.return_type, location: self.location,  method_def: self.method_def)
        self.class.new(type_params: type_params,
                       params: params,
                       block: block,
                       return_type: return_type,
                       method_def: method_def,
                       location: location)
      end

      def to_s
        type_params = !self.type_params.empty? ? "[#{self.type_params.map{|x| "#{x}" }.join(", ")}] " : ""
        params = self.params.to_s
        block = self.block ? " #{self.block}" : ""

        "#{type_params}#{params}#{block} -> #{return_type}"
      end

      def map_type(&block)
        self.class.new(type_params: type_params,
                       params: params.map_type(&block),
                       block: self.block&.yield_self {|blk| blk.map_type(&block) },
                       return_type: yield(return_type),
                       location: location,
                       method_def: method_def)
      end

      # Returns a new method type which can be used for the method implementation type of both `self` and `other`.
      #
      def unify_overload(other)
        type_params = []
        s1 = Substitution.build(self.type_params)
        type_params.push(*s1.dictionary.values.map(&:name))
        s2 = Substitution.build(other.type_params)
        type_params.push(*s2.dictionary.values.map(&:name))

        block = case
                when self.block && other.block
                  self.block.subst(s1) + other.block.subst(s2)
                when self.block
                  self.block.to_optional.subst(s1)
                when other.block
                  other.block.to_optional.subst(s2)
                end

        self.class.new(
          type_params: type_params,
          params: params.subst(s1) + other.params.subst(s2),
          block: block,
          return_type: AST::Types::Union.build(
            types: [return_type.subst(s1),other.return_type.subst(s2)]
          ),
          method_def: method_def,
          location: nil
        )
      end

      def +(other)
        unify_overload(other)
      end

      # Returns a method type which is a super-type of both self and other.
      #   self <: (self | other) && other <: (self | other)
      #
      # Returns nil if self and other are incompatible.
      #
      def |(other)
        self_type_params = Set.new(self.type_params)
        other_type_params = Set.new(other.type_params)

        unless (common_type_params = (self_type_params & other_type_params).to_a).empty?
          fresh_types = common_type_params.map {|name| AST::Types::Var.fresh(name) }
          fresh_names = fresh_types.map(&:name)
          subst = Substitution.build(common_type_params, fresh_types)
          other = other.instantiate(subst)
          type_params = (self_type_params + (other_type_params - common_type_params + Set.new(fresh_names))).to_a
        else
          type_params = (self_type_params + other_type_params).to_a
        end

        params = self.params & other.params or return
        block = case
                when self.block && other.block
                  block_params = self.block.type.params | other.block.type.params
                  block_return_type = AST::Types::Intersection.build(types: [self.block.type.return_type, other.block.type.return_type])
                  block_type = AST::Types::Proc.new(params: block_params,
                                                    return_type: block_return_type,
                                                    location: nil)
                  Block.new(
                    type: block_type,
                    optional: self.block.optional && other.block.optional
                  )
                when self.block && self.block.optional?
                  self.block
                when other.block && other.block.optional?
                  other.block
                when !self.block && !other.block
                  nil
                else
                  return
                end
        return_type = AST::Types::Union.build(types: [self.return_type, other.return_type])

        MethodType.new(
          params: params,
          block: block,
          return_type: return_type,
          type_params: type_params,
          method_def: nil,
          location: nil
        )
      end

      # Returns a method type which is a sub-type of both self and other.
      #   (self & other) <: self && (self & other) <: other
      #
      # Returns nil if self and other are incompatible.
      #
      def &(other)
        self_type_params = Set.new(self.type_params)
        other_type_params = Set.new(other.type_params)

        unless (common_type_params = (self_type_params & other_type_params).to_a).empty?
          fresh_types = common_type_params.map {|name| AST::Types::Var.fresh(name) }
          fresh_names = fresh_types.map(&:name)
          subst = Substitution.build(common_type_params, fresh_types)
          other = other.subst(subst)
          type_params = (self_type_params + (other_type_params - common_type_params + Set.new(fresh_names))).to_a
        else
          type_params = (self_type_params + other_type_params).to_a
        end

        params = self.params | other.params
        block = case
                when self.block && other.block
                  block_params = self.block.type.params & other.block.type.params or return
                  block_return_type = AST::Types::Union.build(types: [self.block.type.return_type, other.block.type.return_type])
                  block_type = AST::Types::Proc.new(params: block_params,
                                                    return_type: block_return_type,
                                                    location: nil)
                  Block.new(
                    type: block_type,
                    optional: self.block.optional || other.block.optional
                  )

                else
                  self.block || other.block
                end

        return_type = AST::Types::Intersection.build(types: [self.return_type, other.return_type])

        MethodType.new(
          params: params,
          block: block,
          return_type: return_type,
          type_params: type_params,
          method_def: nil,
          location: nil
        )
      end
    end
  end
end
