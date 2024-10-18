module Steep
  module Interface
    class Shape
      class MethodOverload
        attr_reader :method_type

        attr_reader :method_defs

        def initialize(method_type, defs)
          @method_type = method_type
          @method_defs = defs.sort_by do |defn|
            buf = +""

            if loc = defn.type.location
              buf << loc.buffer.name.to_s
              buf << ":"
              buf << loc.start_pos.to_s
            end

            buf
          end
          @method_defs.uniq!
        end

        def subst(s)
          overload = MethodOverload.new(method_type.subst(s), [])
          overload.method_defs.replace(method_defs)
          overload
        end

        def method_decls(name)
          method_defs.map do |defn|
            type_name = defn.implemented_in || defn.defined_in

            if name == :new && defn.member.is_a?(RBS::AST::Members::MethodDefinition) && defn.member.name == :initialize
              method_name = SingletonMethodName.new(type_name: type_name, method_name: name)
            else
              method_name =
                if defn.member.kind == :singleton
                  SingletonMethodName.new(type_name: defn.defined_in, method_name: name)
                else
                  # Call the `self?` method an instance method, because the definition is done with instance method definition, not with singleton method
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

      class Methods
        attr_reader :substs, :methods, :resolved_methods

        include Enumerable

        def initialize(substs:, methods:)
          @substs = substs
          @methods = methods
          @resolved_methods = {}
        end

        def key?(name)
          if entry = methods.fetch(name, nil)
            entry.has_method_type?
          else
            false
          end
        end

        def []=(name, entry)
          resolved_methods[name] = nil
          methods[name] = entry
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
            each do |name, _|
              yield name
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
          other.each do |name, entry|
            if block && (old_entry = methods[name])
              methods[name] = yield(name, old_entry, entry)
            else
              methods[name] = entry
            end
          end
        end

        def public_methods
          Methods.new(
            substs: substs,
            methods: methods.reject {|_, entry| entry.private_method? }
          )
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
