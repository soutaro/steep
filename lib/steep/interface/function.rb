module Steep
  module Interface
    class Function
      class Params
        module Utils
          def union(*types, null: false)
            types << AST::Builtin.nil_type if null
            AST::Types::Union.build(types: types)
          end

          def intersection(*types)
            AST::Types::Intersection.build(types: types)
          end
        end

        class PositionalParams
          class Base
            attr_reader :type

            def initialize(type)
              @type = type
            end

            def ==(other)
              other.is_a?(self.class) && other.type == type
            end

            alias eql? ==

            def hash
              self.class.hash ^ type.hash
            end

            def subst(s)
              ty = type.subst(s)

              if ty == type
                self
              else
                _ = self.class.new(ty)
              end
            end

            def var_type
              type
            end

            def map_type(&block)
              if block_given?
                _ = self.class.new(yield type)
              else
                enum_for(:map_type)
              end
            end
          end

          class Required < Base; end
          class Optional < Base; end
          class Rest < Base; end

          attr_reader :head
          attr_reader :tail

          def initialize(head:, tail:)
            @head = head
            @tail = tail
          end

          def self.required(type, tail = nil)
            PositionalParams.new(head: Required.new(type), tail: tail)
          end

          def self.optional(type, tail = nil)
            PositionalParams.new(head: Optional.new(type), tail: tail)
          end

          def self.rest(type, tail = nil)
            PositionalParams.new(head: Rest.new(type), tail: tail)
          end

          def to_ary
            [head, tail]
          end

          def map(&block)
            hd = yield(head)
            tl = tail&.map(&block)

            if head == hd && tail == tl
              self
            else
              PositionalParams.new(head: hd, tail: tl)
            end
          end

          def map_type(&block)
            if block
              map {|param| param.map_type(&block) }
            else
              enum_for :map_type
            end
          end

          def subst(s)
            map_type do |type|
              ty = type.subst(s)
              if ty == type
                type
              else
                ty
              end
            end
          end

          def ==(other)
            other.is_a?(PositionalParams) && other.head == head && other.tail == tail
          end

          alias eql? ==

          def hash
            self.class.hash ^ head.hash ^ tail.hash
          end

          def each(&block)
            if block
              yield head
              tail&.each(&block)
            else
              enum_for(:each)
            end
          end

          def each_type
            if block_given?
              each do |param|
                yield param.type
              end
            else
              enum_for :each_type
            end
          end

          def size
            1 + (tail&.size || 0)
          end

          def self.build(required:, optional:, rest:, trailing:)
            # @type var params: Interface::Function::Params::PositionalParams?
            params = nil
            params = trailing.reverse_each.inject(params) {|params, type| self.required(type, params) }
            params = self.rest(rest, params) if rest
            params = optional.reverse_each.inject(params) {|params, type| self.optional(type, params) }
            params = required.reverse_each.inject(params) {|params, type| self.required(type, params) }

            params
          end

          extend Utils

          # Calculates xs + ys.
          # Never fails.
          def self.merge_for_overload(xs, ys)
            x = xs&.head
            y = ys&.head

            case
            when x.is_a?(Required) && y.is_a?(Required)
              xs or raise
              ys or raise
              required(
                union(x.type, y.type),
                merge_for_overload(xs.tail, ys.tail)
              )
            when x.is_a?(Required) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type, null: true),
                merge_for_overload(xs.tail, ys.tail)
              )
            when x.is_a?(Required) && y.is_a?(Rest)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type, null: true),
                merge_for_overload(xs.tail, ys)
              )
            when x.is_a?(Required) && !y
              xs or raise
              optional(
                union(x.type, null: true),
                merge_for_overload(xs.tail, nil)
              )
            when x.is_a?(Optional) && y.is_a?(Required)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type, null: true),
                merge_for_overload(xs.tail, ys.tail)
              )
            when x.is_a?(Optional) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_overload(xs.tail, ys.tail)
              )
            when x.is_a?(Optional) && y.is_a?(Rest)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_overload(xs.tail, ys)
              )
            when x.is_a?(Optional) && !y
              xs or raise
              optional(
                x.type,
                merge_for_overload(xs.tail, nil)
              )  # == xs
            when x.is_a?(Rest) && y.is_a?(Required)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type, null: true),
                merge_for_overload(xs, ys.tail)
              )
            when x.is_a?(Rest) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_overload(xs, ys.tail)
              )
            when x.is_a?(Rest) && y.is_a?(Rest)
              xs or raise
              ys or raise
              rest(union(x.type, y.type))
            when x.is_a?(Rest) && !y
              xs or raise
            when !x && y.is_a?(Required)
              ys or raise
              optional(
                union(y.type, null: true),
                merge_for_overload(nil, ys.tail)
              )
            when !x && y.is_a?(Optional)
              ys or raise
              optional(
                y.type,
                merge_for_overload(nil, ys.tail)
              )  # == ys
            when !x && y.is_a?(Rest)
              ys or raise
            when !x && !y
              nil
            end
          end

          # xs | ys
          def self.merge_for_union(xs, ys)
            x = xs&.head
            y = ys&.head

            case
            when x.is_a?(Required) && y.is_a?(Required)
              xs or raise
              ys or raise
              required(
                union(x.type, y.type),
                merge_for_union(xs.tail, ys.tail)
              )
            when x.is_a?(Required) && !y
              xs or raise
              optional(
                x.type,
                merge_for_union(xs.tail, nil)
              )
            when x.is_a?(Required) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs.tail, ys.tail)
              )
            when x.is_a?(Required) && y.is_a?(Rest)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs.tail, ys)
              )
            when !x && y.is_a?(Required)
              ys or raise
              optional(
                y.type,
                merge_for_union(nil, ys.tail)
              )
            when !x && !y
              nil
            when !x && y.is_a?(Optional)
              ys or raise
              PositionalParams.new(head: y, tail: merge_for_union(nil, ys.tail))
            when !x && y.is_a?(Rest)
              ys or raise
            when x.is_a?(Optional) && y.is_a?(Required)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs.tail, ys.tail)
              )
            when x.is_a?(Optional) && !y
              xs or raise
              PositionalParams.new(head: x, tail: merge_for_union(xs.tail, nil)) # == xs
            when x.is_a?(Optional) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs.tail, ys.tail)
              )
            when x.is_a?(Optional) && y.is_a?(Rest)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs.tail, ys.tail)
              )
            when x.is_a?(Rest) && y.is_a?(Required)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs, ys.tail)
              )
            when x.is_a?(Rest) && !y
              xs or raise
            when x.is_a?(Rest) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                union(x.type, y.type),
                merge_for_union(xs, ys.tail)
              )
            when x.is_a?(Rest) && y.is_a?(Rest)
              xs or raise
              ys or raise
              rest(
                union(x.type, y.type)
              )
            end
          end

          # Calculates xs & ys.
          # Raises when failed.
          #
          def self.merge_for_intersection(xs, ys)
            x = xs&.head
            y = ys&.head

            case
            when x.is_a?(Required) && y.is_a?(Required)
              xs or raise
              ys or raise
              required(
                intersection(x.type, y.type),
                merge_for_intersection(xs.tail, ys.tail)
              )
            when x.is_a?(Required) && !y
              raise
            when x.is_a?(Required) && y.is_a?(Optional)
              xs or raise
              ys or raise
              required(
                intersection(x.type, y.type),
                merge_for_intersection(xs.tail, ys.tail)
              )
            when x.is_a?(Required) && y.is_a?(Rest)
              xs or raise
              ys or raise
              required(
                intersection(x.type, y.type),
                merge_for_intersection(xs.tail, ys)
              )
            when !x && y.is_a?(Required)
              raise
            when !x && !y
              nil
            when !x && y.is_a?(Optional)
              nil
            when !x && y.is_a?(Rest)
              nil
            when x.is_a?(Optional) && y.is_a?(Required)
              xs or raise
              ys or raise
              required(
                intersection(x.type, y.type),
                merge_for_intersection(xs.tail, ys.tail)
              )
            when x.is_a?(Optional) && !y
              nil
            when x.is_a?(Optional) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                intersection(x.type, y.type),
                merge_for_intersection(xs.tail, ys.tail)
              )
            when x.is_a?(Optional) && y.is_a?(Rest)
              xs or raise
              ys or raise
              optional(
                intersection(x.type, y.type),
                merge_for_intersection(xs.tail, ys)
              )
            when x.is_a?(Rest) && y.is_a?(Required)
              xs or raise
              ys or raise
              required(
                intersection(x.type, y.type),
                merge_for_intersection(xs, ys.tail)
              )
            when x.is_a?(Rest) && !y
              nil
            when x.is_a?(Rest) && y.is_a?(Optional)
              xs or raise
              ys or raise
              optional(
                intersection(x.type, y.type),
                merge_for_intersection(xs, ys.tail)
              )
            when x.is_a?(Rest) && y.is_a?(Rest)
              rest(intersection(x.type, y.type))
            end
          end
        end

        class KeywordParams
          attr_reader :requireds
          attr_reader :optionals
          attr_reader :rest

          def initialize(requireds: {}, optionals: {}, rest: nil)
            @requireds = requireds
            @optionals = optionals
            @rest = rest
          end

          def ==(other)
            other.is_a?(KeywordParams) &&
              other.requireds == requireds &&
              other.optionals == optionals &&
              other.rest == rest
          end

          alias eql? ==

          def hash
            self.class.hash ^ requireds.hash ^ optionals.hash ^ rest.hash
          end

          def update(requireds: self.requireds, optionals: self.optionals, rest: self.rest)
            KeywordParams.new(
              requireds: requireds,
              optionals: optionals,
              rest: rest
            )
          end

          def empty?
            requireds.empty? && optionals.empty? && rest.nil?
          end

          def each(&block)
            if block
              requireds.each(&block)
              optionals.each(&block)
              if rest
                yield [nil, rest]
              end
            else
              enum_for :each
            end
          end

          def each_type
            if block_given?
              each do |_, type|
                yield type
              end
            else
              enum_for :each_type
            end
          end

          def map_type(&block)
            if block
              rs = requireds.transform_values(&block)
              os = optionals.transform_values(&block)
              r = rest&.yield_self(&block)

              if requireds == rs && optionals == os && rest == r
                self
              else
                update(requireds: rs, optionals: os, rest: r)
              end
            else
              enum_for(:map_type)
            end
          end

          def subst(s)
            map_type do |type|
              ty = type.subst(s)
              if ty == type
                type
              else
                ty
              end
            end
          end

          def size
            requireds.size + optionals.size + (rest ? 1 : 0)
          end

          def keywords
            Set[] + requireds.keys + optionals.keys
          end

          include Utils

          # For overloading
          def +(other)
            requireds = {} #: Hash[Symbol, AST::Types::t]
            optionals = {} #: Hash[Symbol, AST::Types::t]

            all_keys = Set[] + self.requireds.keys + self.optionals.keys + other.requireds.keys + other.optionals.keys
            all_keys.each do |key|
              case
              when t = self.requireds[key]
                case
                when s = other.requireds[key]
                  requireds[key] = union(t, s)
                when s = other.optionals[key]
                  optionals[key] = union(t, s, null: true)
                when s = other.rest
                  optionals[key] = union(t, s, null: true)
                else
                  optionals[key] = union(t, null: true)
                end
              when t = self.optionals[key]
                case
                when s = other.requireds[key]
                  optionals[key] = union(t, s, null: true)
                when s = other.optionals[key]
                  optionals[key] = union(t, s)
                when s = other.rest
                  optionals[key] = union(t, s)
                else
                  optionals[key] = t
                end
              when t = self.rest
                case
                when s = other.requireds[key]
                  optionals[key] = union(t, s, null: true)
                when s = other.optionals[key]
                  optionals[key] = union(t, s)
                when s = other.rest
                  # cannot happen
                else
                  # nop
                end
              else
                case
                when s = other.requireds[key]
                  optionals[key] = union(s, null: true)
                when s = other.optionals[key]
                  optionals[key] = s
                when s = other.rest
                  # nop
                else
                  # cannot happen
                end
              end
            end

            if self.rest && other.rest
              rest = union(self.rest, other.rest)
            else
              rest = self.rest || other.rest
            end

            KeywordParams.new(requireds: requireds, optionals: optionals, rest: rest)
          end

          # For union
          def |(other)
            requireds = {} #: Hash[Symbol, AST::Types::t]
            optionals = {} #: Hash[Symbol, AST::Types::t]

            all_keys = Set[] + self.requireds.keys + self.optionals.keys + other.requireds.keys + other.optionals.keys
            all_keys.each do |key|
              case
              when t = self.requireds[key]
                case
                when s = other.requireds[key]
                  requireds[key] = union(t, s)
                when s = other.optionals[key]
                  optionals[key] = union(t, s)
                when s = other.rest
                  optionals[key] = union(t, s)
                else
                  optionals[key] = t
                end
              when t = self.optionals[key]
                case
                when s = other.requireds[key]
                  optionals[key] = union(t, s)
                when s = other.optionals[key]
                  optionals[key] = union(t, s)
                when s = other.rest
                  optionals[key] = union(t, s)
                else
                  optionals[key] = t
                end
              when t = self.rest
                case
                when s = other.requireds[key]
                  optionals[key] = union(t, s)
                when s = other.optionals[key]
                  optionals[key] = union(t, s)
                when s = other.rest
                  # cannot happen
                else
                  # nop
                end
              else
                case
                when s = other.requireds[key]
                  optionals[key] = s
                when s = other.optionals[key]
                  optionals[key] = s
                when s = other.rest
                  # nop
                else
                  # cannot happen
                end
              end
            end

            rest =
              if self.rest && other.rest
                union(self.rest, other.rest)
              else
                self.rest || other.rest
              end

            KeywordParams.new(requireds: requireds, optionals: optionals, rest: rest)
          end

          # For intersection
          def &(other)
            requireds = {} #: Hash[Symbol, AST::Types::t]
            optionals = {} #: Hash[Symbol, AST::Types::t]

            all_keys = Set[] + self.requireds.keys + self.optionals.keys + other.requireds.keys + other.optionals.keys
            all_keys.each do |key|
              case
              when t = self.requireds[key]
                case
                when s = other.requireds[key]
                  requireds[key] = intersection(t, s)
                when s = other.optionals[key]
                  requireds[key] = intersection(t, s)
                when s = other.rest
                  requireds[key] = intersection(t, s)
                else
                  return nil
                end
              when t = self.optionals[key]
                case
                when s = other.requireds[key]
                  requireds[key] = intersection(t, s)
                when s = other.optionals[key]
                  optionals[key] = intersection(t, s)
                when s = other.rest
                  optionals[key] = intersection(t, s)
                else
                  # nop
                end
              when t = self.rest
                case
                when s = other.requireds[key]
                  requireds[key] = intersection(t, s)
                when s = other.optionals[key]
                  optionals[key] = intersection(t, s)
                when s = other.rest
                  # cannot happen
                else
                  # nop
                end
              else
                case
                when s = other.requireds[key]
                  return nil
                when s = other.optionals[key]
                  # nop
                when s = other.rest
                  # nop
                else
                  # cannot happen
                end
              end
            end

            rest =
              if self.rest && other.rest
                intersection(self.rest, other.rest)
              else
                nil
              end

            KeywordParams.new(requireds: requireds, optionals: optionals, rest: rest)
          end
        end

        def required
          array = [] #: Array[AST::Types::t]

          positional_params&.each do |param|
            case param
            when PositionalParams::Required
              array << param.type
            else
              break
            end
          end

          array
        end

        def optional
          array = [] #: Array[AST::Types::t]

          positional_params&.each do |param|
            case param
            when PositionalParams::Required
              # skip
            when PositionalParams::Optional
              array << param.type
            else
              break
            end
          end

          array
        end

        def rest
          positional_params&.each do |param|
            case param
            when PositionalParams::Required, PositionalParams::Optional
              # skip
            when PositionalParams::Rest
              return param.type
            end
          end

          nil
        end

        def trailing
          array = [] #: Array[AST::Types::t]
          trailing = false

          positional_params&.each do |param|
            case param
            when PositionalParams::Required
              array << param.type if trailing
            when PositionalParams::Optional, PositionalParams::Rest
              trailing = true
            end
          end

          array
        end

        attr_reader :positional_params
        attr_reader :keyword_params

        def self.build(required: [], optional: [], rest: nil, trailing: [], required_keywords: {}, optional_keywords: {}, rest_keywords: nil)
          positional_params = PositionalParams.build(required: required, optional: optional, rest: rest, trailing: trailing)
          keyword_params = KeywordParams.new(requireds: required_keywords, optionals: optional_keywords, rest: rest_keywords)
          new(positional_params: positional_params, keyword_params: keyword_params)
        end

        def initialize(positional_params:, keyword_params:)
          @positional_params = positional_params
          @keyword_params = keyword_params
        end

        def update(positional_params: self.positional_params, keyword_params: self.keyword_params)
          self.class.new(positional_params: positional_params, keyword_params: keyword_params)
        end

        def first_param
          positional_params&.head
        end

        def with_first_param(param)
          update(
            positional_params: PositionalParams.new(
              head: param,
              tail: positional_params
            )
          )
        end

        def has_positional?
          positional_params ? true : false
        end

        def self.empty
          self.new(positional_params: nil, keyword_params: KeywordParams.new)
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.positional_params == positional_params &&
            other.keyword_params == keyword_params
        end

        alias eql? ==

        def hash
          self.class.hash ^ positional_params.hash ^ keyword_params.hash
        end

        def flat_unnamed_params
          if positional_params
            positional_params.each.with_object([]) do |param, types|
              case param
              when PositionalParams::Required
                types << [:required, param.type]
              when PositionalParams::Optional
                types << [:optional, param.type]
              end
            end
          else
            []
          end
        end

        def flat_keywords
          required_keywords.merge(optional_keywords)
        end

        def required_keywords
          keyword_params.requireds
        end

        def optional_keywords
          keyword_params.optionals
        end

        def rest_keywords
          keyword_params.rest
        end

        def has_keywords?
          !keyword_params.empty?
        end

        def each_positional_param(&block)
          if block_given?
            if positional_params
              positional_params.each(&block)
            end
          else
            enum_for :each_positional_param
          end
        end

        def without_keywords
          update(keyword_params: KeywordParams.new)
        end

        def drop_first
          case
          when positional_params
            update(positional_params: positional_params.tail)
          when has_keywords?
            without_keywords()
          else
            raise "Cannot drop from empty params"
          end
        end

        def each_type(&block)
          if block
            positional_params&.each_type(&block)
            keyword_params.each_type(&block)
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
          each_type.all? { _1.free_variables.empty? }
        end

        def subst(s)
          return self if s.empty?
          return self if empty?
          return self if each_type.none? {|t| s.apply?(t) }

          pp = positional_params
          kp = keyword_params

          if positional_params && positional_params.each_type.any? {|t| s.apply?(t) }
            pp = positional_params.subst(s)
          end
          if keyword_params && keyword_params.each_type.any? {|t| s.apply?(t) }
            kp = keyword_params.subst(s)
          end

          self.class.new(positional_params: pp, keyword_params: kp)
        end

        def size
          (positional_params&.size || 0) + keyword_params.size
        end

        def to_s
          required = self.required.map {|ty| ty.to_s }
          optional = self.optional.map {|ty| "?#{ty}" }
          rest = self.rest ? ["*#{self.rest}"] : [] #: Array[String]
          required_keywords = keyword_params.requireds.map {|name, type| "#{name}: #{type}" }
          optional_keywords = keyword_params.optionals.map {|name, type| "?#{name}: #{type}"}
          rest_keywords = keyword_params.rest ? ["**#{keyword_params.rest}"] : [] #: Array[String]
          "(#{(required + optional + rest + required_keywords + optional_keywords + rest_keywords).join(", ")})"
        end

        def map_type(&block)
          self.class.new(
            positional_params: positional_params&.map_type(&block),
            keyword_params: keyword_params.map_type(&block)
          )
        end

        def empty?
          !has_positional? && !has_keywords?
        end

        # Returns true if all arguments are non-required.
        def optional?
          required.empty? && required_keywords.empty?
        end

        # self + params returns a new params for overloading.
        #
        def +(other)
          pp = PositionalParams.merge_for_overload(positional_params, other.positional_params)
          kp = keyword_params + other.keyword_params
          Params.new(positional_params: pp, keyword_params: kp)
        end

        # Returns the intersection between self and other.
        # Returns nil if the intersection cannot be computed.
        #
        #   (self & other) <: self
        #   (self & other) <: other
        #
        # `self & other` accept `arg` if `arg` is acceptable for both of `self` and `other`.
        #
        def &(other)
          pp = PositionalParams.merge_for_intersection(positional_params, other.positional_params) rescue return
          kp = keyword_params & other.keyword_params or return
          Params.new(positional_params: pp, keyword_params: kp)
        end

        # Returns the union between self and other.
        #
        #    self <: (self | other)
        #   other <: (self | other)
        #
        # `self | other` accept `arg` if `self` accepts `arg` or `other` accepts `arg`.
        #
        def |(other)
          pp = PositionalParams.merge_for_union(positional_params, other.positional_params) rescue return
          kp = keyword_params | other.keyword_params or return
          Params.new(positional_params: pp, keyword_params: kp)
        end
      end

      attr_reader :params
      attr_reader :return_type
      attr_reader :location

      def initialize(params:, return_type:, location:)
        @params = params
        @return_type = return_type
        @location = location
      end

      def ==(other)
        other.is_a?(Function) && other.params == params && other.return_type == return_type
      end

      alias eql? ==

      def hash
        self.class.hash ^ params.hash ^ return_type.hash
      end

      def free_variables
        @fvs ||= Set[].tap do |fvs|
          # @type var fvs: Set[AST::Types::variable]
          fvs.merge(params.free_variables) if params
          fvs.merge(return_type.free_variables)
        end
      end

      def subst(s)
        return self if s.empty?

        ps = params.subst(s) if params
        ret = return_type.subst(s)

        if ps == params && ret == return_type
          self
        else
          Function.new(
            params: ps,
            return_type: ret,
            location: location
          )
        end
      end

      def each_type(&block)
        if block
          params&.each_type(&block)
          yield return_type
        else
          enum_for :each_type
        end
      end

      alias each_child each_type

      def map_type(&block)
        Function.new(
          params: params&.map_type(&block),
          return_type: yield(return_type),
          location: location
        )
      end

      def with(params: self.params, return_type: self.return_type)
        Function.new(
          params: params,
          return_type: return_type,
          location: location
        )
      end

      def accept_one_arg?
        return false unless params
        return false unless params.keyword_params.requireds.empty?
        head = params.positional_params or return false

        case head.head
        when Params::PositionalParams::Required
          !head.tail.is_a?(Params::PositionalParams::Required)
        else
          true
        end
      end

      def to_s
        if params
          "#{params} -> #{return_type}"
        else
          "(?) -> #{return_type}"
        end
      end

      def closed?
        if params
          params.closed? && return_type.free_variables.empty?
        else
          return_type.free_variables.empty?
        end
      end
    end
  end
end
