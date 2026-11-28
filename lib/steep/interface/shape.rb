module Steep
  module Interface
    class Shape
      class MethodOverload
        attr_reader :method_type

        attr_reader :method_defs

        def initialize(method_type, defs)
          @method_type = method_type
          if defs.size > 1
            @method_defs = defs.sort_by do |defn|
              if loc = defn.type.location
                [loc.buffer.name.to_s, loc.start_pos]
              else
                ["", -1]
              end
            end
            @method_defs.uniq!
          else
            @method_defs = defs.dup
          end
        end

        def subst(s)
          method_type_ = method_type.subst(s)
          return self if method_type_.equal?(method_type)

          overload = MethodOverload.new(method_type_, [])
          overload.method_defs.replace(method_defs)
          overload
        end

        def method_decls(name)
          method_defs.map do |defn|
            type_name = defn.implemented_in || defn.defined_in

            case
            when name == :new && defn.member.is_a?(RBS::AST::Members::MethodDefinition) && defn.member.name == :initialize
              method_name = SingletonMethodName.new(type_name: type_name, method_name: name)
            when name == :new && defn.member.is_a?(RBS::AST::Ruby::Members::DefMember) && defn.member.name == :initialize
              method_name = SingletonMethodName.new(type_name: type_name, method_name: name)
            else
              method_name =
                case defn.member
                when RBS::AST::Members::Base
                  if defn.member.kind == :singleton
                    SingletonMethodName.new(type_name: defn.defined_in, method_name: name)
                  else
                    # Call the `self?` method an instance method, because the definition is done with instance method definition, not with singleton method
                    InstanceMethodName.new(type_name: defn.defined_in, method_name: name)
                  end
                when RBS::AST::Ruby::Members::DefMember, RBS::AST::Ruby::Members::AttributeMember
                  InstanceMethodName.new(type_name: defn.defined_in, method_name: name)
                end
            end

            TypeInference::MethodCall::MethodDecl.new(method_def: defn, method_name: method_name)
          end
        end
      end

      class Entry
        attr_reader :method_name

        def initialize(overloads: nil, private_method:, method_name:, &block)
          @overloads = overloads
          @generator = block
          @private_method = private_method
          @method_name = method_name
        end

        def force
          unless @overloads
            @overloads = @generator&.call
            @generator = nil
          end
        end

        def overloads
          force
          @overloads or raise
        end

        def method_types
          overloads.map(&:method_type)
        end

        def has_method_type?
          force
          @overloads ? true : false
        end

        def to_s
          if @generator
            "<< Lazy entry >>"
          else
            "{ #{method_types.join(" || ")} }"
          end
        end

        def private_method?
          @private_method
        end

        def public_method?
          !private_method?
        end
      end

      # The entries of the methods of a RBS definition
      #
      # It works like `Hash[Symbol, Entry]`, but builds each entry when it is requested --
      # the method of the definition is resolved and its method types are converted then.
      #
      class DefinitionEntries
        attr_reader :methods

        def initialize(methods, entries: {}, public_only: false, &block)
          @methods = methods
          @entries = entries
          @public_only = public_only
          @block = block
        end

        def key?(name)
          if @public_only
            if method = methods[name]
              method.public?
            else
              false
            end
          else
            methods.key?(name)
          end
        end

        def [](name)
          if entry = @entries[name]
            entry if !@public_only || entry.public_method?
          elsif method = methods[name]
            if !@public_only || method.public?
              @entries[name] = @block.call(name, method)
            end
          end
        end

        def fetch(name)
          self[name] or raise KeyError, "key not found: #{name.inspect}"
        end

        def private_method?(name)
          if method = methods[name]
            method.private?
          else
            false
          end
        end

        def each_key(&block)
          if block
            if @public_only
              methods.each do |name, method|
                yield name if method.public?
              end
            else
              methods.each_key(&block)
            end
          else
            enum_for :each_key
          end
        end

        # Returns the entries of the public methods, that share the entries with `self`
        #
        def public_entries
          if @public_only
            self
          else
            DefinitionEntries.new(methods, entries: @entries, public_only: true, &@block)
          end
        end
      end

      class Methods
        attr_reader :substs, :methods, :resolved_methods

        include Enumerable

        def initialize(substs:, methods:)
          @substs = substs
          @methods = methods
          @resolved_methods = {}
        end

        def key?(name)
          case methods = self.methods
          when DefinitionEntries
            # The methods of a definition always have method types
            methods.key?(name)
          else
            if entry = methods[name]
              entry.has_method_type?
            else
              false
            end
          end
        end

        def []=(name, entry)
          methods = self.methods
          methods.is_a?(Hash) or raise "The methods of a definition cannot be updated"

          resolved_methods[name] = nil
          methods[name] = entry
        end

        def private_method?(name)
          case methods = self.methods
          when DefinitionEntries
            methods.private_method?(name)
          else
            methods.fetch(name).private_method?
          end
        end

        def [](name)
          return nil unless key?(name)

          resolved_methods[name] ||= begin
            entry = methods.fetch(name)
            Entry.new(
              method_name: name,
              overloads: entry.overloads.map do |overload|
                overload.subst(subst)
              end,
              private_method: entry.private_method?
            )
          end
        end

        def each(&block)
          if block
            methods.each_key do |name|
              entry = self[name] or next
              yield [name, entry]
            end
          else
            enum_for :each
          end
        end

        def each_name(&block)
          if block
            # `key?` decides if the method exists without applying the substitutions,
            # unlike `each` that resolves every entry
            methods.each_key do |name|
              yield name if key?(name)
            end
          else
            enum_for :each_name
          end
        end

        def subst
          @subst ||= begin
            substs.each_with_object(Substitution.empty) do |s, ss|
              ss.merge!(s, overwrite: true)
            end
          end
        end

        def push_substitution(subst)
          Methods.new(substs: [*substs, subst], methods: methods)
        end

        def merge!(other, &block)
          methods = self.methods
          methods.is_a?(Hash) or raise "The methods of a definition cannot be updated"

          other.methods.each_key do |name|
            # `key?` skips the entries without method types, like `each` did, but doesn't
            # resolve the others -- applying the substitutions of `other` is deferred to a
            # lazy entry, and the visibility is copied from the unresolved entry
            next unless other.key?(name)

            entry = Entry.new(method_name: name, private_method: other.private_method?(name)) do
              other[name]&.overloads
            end

            if block && (old_entry = methods[name])
              methods[name] = yield(name, old_entry, entry)
            else
              methods[name] = entry
            end
          end
        end

        def public_methods
          case methods = self.methods
          when DefinitionEntries
            Methods.new(substs: substs, methods: methods.public_entries)
          else
            Methods.new(
              substs: substs,
              methods: methods.reject {|_, entry| entry.private_method? }
            )
          end
        end
      end

      attr_reader :type
      attr_reader :methods

      def initialize(type:, private:, methods: nil)
        @type = type
        @private = private
        @methods = methods || Methods.new(substs: [], methods: {})
      end

      def to_s
        "#<#{self.class.name}: type=#{type}, private?=#{@private}, methods={#{methods.each_name.sort.join(", ")}}"
      end

      def update(type: self.type, methods: self.methods)
        _ = self.class.new(type: type, private: private?, methods: methods)
      end

      def subst(s, type: nil)
        ty =
          if type
            type
          else
            self.type.subst(s)
          end

        Shape.new(type: ty, private: private?, methods: methods.push_substitution(s))
      end

      def private?
        @private
      end

      def public?
        !private?
      end

      def public_shape
        if public?
          self
        else
          @public_shape ||= Shape.new(
            type: type,
            private: false,
            methods: methods.public_methods
          )
        end
      end
    end
  end
end
