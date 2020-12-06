module Steep
  module Interface
    class Function
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
    end
  end
end
