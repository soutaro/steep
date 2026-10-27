module Steep
  module TypeInference
    # The ordered semantics of the overloads of a method at a call site.
    #
    # The first overload that accepts an argument is the one called, so that `(Integer) -> A | (Numeric) -> B` reads
    # as `(Integer -> A) & ((Numeric & !Integer) -> B)`: the arguments that reach an overload are the ones its
    # parameters accept and no earlier overload accepts.
    #
    # The arguments of a call are a tuple of the positional arguments and the values of the keyword arguments
    # (`Shape`), and the domain of an overload for the call is the tuple of the parameter types the arguments are
    # matched with. The tuple of the argument types is carved by the domains in order, as a union of tuples: the
    # parts of the tuple inside a domain go to the overload, and the parts outside go on to the next one.
    class OrderedOverloads
      # The positional arguments and the keyword arguments of a call, in the order of the components of the tuple
      class Shape
        attr_reader :positionals

        attr_reader :keywords

        # `:given` with a block, `:none` without, and `:unknown` with a block pass argument
        attr_reader :block

        def initialize(positionals:, keywords:, block:)
          @positionals = positionals
          @keywords = keywords
          @block = block
        end

        # The shape of the arguments; `nil` when they have a splat, a keyword splat, a forwarded argument, or a
        # keyword that is not a symbol
        def self.from_arguments(arguments, block_given:)
          positionals = [] #: Array[Parser::AST::Node]
          keywords = {} #: Hash[Symbol, Parser::AST::Node]
          block = block_given ? :given : :none #: block

          arguments.each do |arg|
            case arg.type
            when :splat, :forwarded_args
              return nil
            when :block_pass
              block = :unknown
            when :kwargs
              arg.children.each do |pair|
                return nil unless pair.type == :pair
                key, value = pair.children
                return nil unless key.type == :sym
                keywords[key.children[0]] = value
              end
            else
              positionals << arg
            end
          end

          new(positionals: positionals, keywords: keywords, block: block)
        end

        # The nodes of the components of the tuple
        def nodes
          positionals + keywords.values
        end

        # The domain of a method type for this shape: the type of each component, or `nil` when the method type does
        # not accept the shape (the number of the positional arguments, a keyword, or the block)
        #
        # The type parameters of the method type are read as their upper bounds, or `top`.
        def domain(method_type)
          unless method_type.type_params.empty?
            names = method_type.type_params.map(&:name)
            bounds = method_type.type_params.map {|param| param.upper_bound || AST::Builtin.top_type }
            method_type = method_type.instantiate(Interface::Substitution.build(names, bounds))
          end

          case block
          when :given
            return nil unless method_type.block
          when :none
            return nil if method_type.block&.required?
          end

          params = method_type.type.params
          unless params
            # An untyped function accepts anything
            return Array.new(nodes.size, AST::Builtin.top_type)
          end

          types = [] #: Array[AST::Types::t]

          required = params.required
          optional = params.optional
          rest = params.rest
          positionals.each_with_index do |_, index|
            case
            when index < required.size
              types << required.fetch(index)
            when index < required.size + optional.size
              types << optional.fetch(index - required.size)
            when rest
              types << rest
            else
              return nil
            end
          end
          return nil if positionals.size < required.size

          keywords.each_key do |name|
            case
            when (type = params.required_keywords[name])
              types << type
            when (type = params.optional_keywords[name])
              types << type
            when (type = params.rest_keywords)
              types << type
            else
              return nil
            end
          end
          return nil unless params.required_keywords.each_key.all? {|name| keywords.key?(name) }

          types
        end
      end

      # The bound on the number of tuples the arguments are carved into
      MAX_TUPLES = 32

      attr_reader :emptiness

      attr_reader :simplifier

      attr_reader :bounds

      def initialize(emptiness:, simplifier:, bounds:)
        @emptiness = emptiness
        @simplifier = simplifier
        @bounds = bounds
      end

      # `true` if the overload takes a part of the tuple: every component is in the domain, or has a part in it that
      # is known to be inhabited
      #
      # An overlap the class hierarchy does not show, like the one of two interfaces, takes nothing, so that the
      # overload the whole argument is accepted by keeps it.
      def takes_part?(tuple, domain)
        tuple.each_with_index.all? do |type, index|
          param = domain.fetch(index)
          empty?(outside(type, param)) || emptiness.known_inhabited?(inside(type, param), bounds: bounds)
        end
      end

      # Carves the tuples by the domain: returns the parts inside the domain, which are the tuples of the types the
      # components are read as by the overload, and the parts outside, which go on to the next overload
      #
      # `[c1, c2] & [d1, d2]` is `[c1 & d1, c2 & d2]`, and `[c1, c2] & ![d1, d2]` is
      # `[c1 & !d1, c2] | [c1 & d1, c2 & !d2]`. A tuple the overload takes no part of (`takes_part?`) goes outside
      # as it is. Returns `nil` when there are more than `MAX_TUPLES` tuples.
      def carve(tuples, domain)
        parts = [] #: Array[tuple]
        rest = [] #: Array[tuple]

        tuples.each do |tuple|
          inside_types = [] #: tuple
          outside_types = [] #: Array[AST::Types::t?]

          taken = tuple.each_with_index.all? do |type, index|
            param = domain.fetch(index)
            outside = outside(type, param)

            if empty?(outside)
              # The component is in the domain
              inside_types << type
              outside_types << nil
              true
            else
              inner = inside(type, param)
              if emptiness.known_inhabited?(inner, bounds: bounds)
                inside_types << inner
                outside_types << outside
                true
              else
                false
              end
            end
          end

          unless taken
            rest << tuple
            next
          end

          parts << inside_types

          outside_types.each_with_index do |outside, index|
            next unless outside

            rest << inside_types.take(index) + [outside] + tuple.drop(index + 1)
            return nil if rest.size > MAX_TUPLES
          end
        end

        [parts, rest]
      end

      def inside(type, param)
        simplifier.intersect(type, param, bounds: bounds, candidates: [type, param])
      end

      def outside(type, param)
        simplifier.intersect(type, AST::Types::Negation.build(type: param), bounds: bounds, candidates: [type])
      end

      # `true` if the type has no value by the evidence of the class hierarchy
      def empty?(type)
        emptiness.check(type, mode: :inhabitation, bounds: bounds).empty_in_rbs_or_stronger?
      end
    end
  end
end
