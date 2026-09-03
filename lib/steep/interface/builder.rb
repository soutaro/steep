module Steep
  module Interface
    class Builder
      class Config
        attr_reader :self_type, :class_type, :instance_type, :variable_bounds

        def initialize(self_type:, class_type: nil, instance_type: nil, variable_bounds:)
          @self_type = self_type
          @class_type = class_type
          @instance_type = instance_type
          @variable_bounds = variable_bounds
        end

        def self.empty
          new(self_type: nil, variable_bounds: {})
        end

        def subst
          if self_type || class_type || instance_type
            Substitution.build([], [], self_type: self_type, module_type: class_type, instance_type: instance_type)
          end
        end

        def validate_self_type
          validate_fvs(:self_type, self_type)
        end

        def validate_instance_type
          validate_fvs(:instance_type, instance_type)
        end

        def validate_class_type
          validate_fvs(:class_type, class_type)
        end

        def validate_fvs(name, type)
          if type
            fvs = type.free_variables
            if fvs.include?(AST::Types::Self.instance)
              raise "#{name} cannot include 'self' type: #{type}"
            end
            if fvs.include?(AST::Types::Instance.instance)
              Steep.logger.fatal { "#{name} cannot include 'instance' type: #{type}" }
              raise "#{name} cannot include 'instance' type: #{type}"
            end
            if fvs.include?(AST::Types::Class.instance)
              raise "#{name} cannot include 'class' type: #{type}"
            end
          end
        end

        def upper_bound(a)
          variable_bounds.fetch(a, nil)
        end
      end

      attr_reader :factory, :object_shape_cache, :union_shape_cache, :singleton_shape_cache, :closed_shape_cache, :implicitly_returns_nil

      def initialize(factory, implicitly_returns_nil:)
        @factory = factory
        @object_shape_cache = {}
        @union_shape_cache = {}
        @singleton_shape_cache = {}
        @closed_shape_cache = {}
        @method_overload_cache = {}
        @method_overload_index = {}
        @method_entry_cache = {}
        @method_entry_index = {}
        @implicitly_returns_nil = implicitly_returns_nil
      end

      def shape(type, config)
        if stats = Subtyping::Stats.active
          stats.measure_shape(type) do
            shape0(type, config)
          end
        else
          shape0(type, config)
        end
      end

      def shape0(type, config)
        Steep.logger.tagged(-> { "shape(#{type})" }) do
          if closed_shape?(type)
            closed_shape(type, config)
          elsif shape = raw_shape(type, config)
            # Optimization that skips unnecessary substitution
            if type.free_variables.include?(AST::Types::Self.instance)
              shape
            else
              if s = config.subst
                shape.subst(s)
              else
                shape
              end
            end
          end
        end
      end

      def fetch_cache(cache, key)
        if cache.key?(key)
          return cache.fetch(key)
        end

        cache[key] = yield
      end

      def closed_shape?(type)
        type.free_variables.empty? && (closed_shape_cache.key?(type) || config_free_shape?(type))
      end

      def closed_shape(type, config)
        closed_shape_cache.fetch(type) do
          closed_shape_cache[type] = raw_shape(type, config)
        end
      end

      def cached_raw_shape(type, config)
        if closed_shape?(type)
          closed_shape(type, config)
        else
          raw_shape(type, config)
        end
      end

      def config_free_shape?(type)
        case type
        when AST::Types::Name::Instance, AST::Types::Name::Singleton, AST::Types::Literal, AST::Types::Nil,
             AST::Types::Boolean, AST::Types::Logic::Base, AST::Types::Proc, AST::Types::Tuple, AST::Types::Record
          true
        when AST::Types::Union, AST::Types::Intersection
          type.types.all? {|ty| config_free_shape?(ty) }
        when AST::Types::Name::Alias
          # The free variables of an alias type do not include the ones in its expansion
          expanded = factory.expand_alias(type)
          expanded.free_variables.empty? && config_free_shape?(expanded)
        else
          false
        end
      end

      def raw_shape(type, config)
        case type
        when AST::Types::Self
          config.validate_self_type
          self_type = config.self_type or raise
          self_shape(self_type, config)
        when AST::Types::Instance
          config.validate_instance_type
          instance_type = config.instance_type or raise
          raw_shape(instance_type, config)
        when AST::Types::Class
          config.validate_class_type
          klass_type = config.class_type or raise
          raw_shape(klass_type, config)
        when AST::Types::Name::Singleton
          singleton_shape(type.name).subst(class_subst(type))
        when AST::Types::Name::Instance
          object_shape(type.name).subst(class_subst(type).merge(app_subst(type)), type: type)
        when AST::Types::Name::Interface
          object_shape(type.name).subst(interface_subst(type).merge(app_subst(type)), type: type)
        when AST::Types::Union
          groups = type.types.group_by do |type|
            if type.is_a?(AST::Types::Literal)
              type.back_type
            else
              nil
            end
          end

          shapes = [] #: Array[Shape]
          groups.each do |name, types|
            if name
              union = AST::Types::Union.build(types: types)
              subst = class_subst(name).update(self_type: union)
              shapes << object_shape(name.name).subst(subst, type: union)
            else
              shapes.concat(types.map {|ty| cached_raw_shape(ty, config) or return })
            end
          end

          fetch_cache(union_shape_cache, type) do
            union_shape(type, shapes)
          end
        when AST::Types::Intersection
          shapes = type.types.map do |type|
            cached_raw_shape(type, config) or return
          end
          intersection_shape(type, shapes)
        when AST::Types::Name::Alias
          expanded = factory.expand_alias(type)
          if shape = cached_raw_shape(expanded, config)
            shape.update(type: type)
          end
        when AST::Types::Literal
          instance_type = type.back_type
          subst = class_subst(instance_type).update(self_type: type)
          object_shape(instance_type.name).subst(subst, type: type)
        when AST::Types::Boolean
          true_shape =
            (object_shape(RBS::BuiltinNames::TrueClass.name)).
              subst(class_subst(AST::Builtin::TrueClass.instance_type).update(self_type: type))
          false_shape =
            (object_shape(RBS::BuiltinNames::FalseClass.name)).
              subst(class_subst(AST::Builtin::FalseClass.instance_type).update(self_type: type))
          union_shape(type, [true_shape, false_shape])
        when AST::Types::Proc
          shape = object_shape(AST::Builtin::Proc.module_name).subst(class_subst(AST::Builtin::Proc.instance_type).update(self_type: type))
          proc_shape(type, shape)
        when AST::Types::Tuple
          tuple_shape(type) do |array|
            object_shape(array.name).subst(
              class_subst(array).update(self_type: type).merge(app_subst(array))
            )
          end
        when AST::Types::Record
          record_shape(type) do |hash|
            object_shape(hash.name).subst(
              class_subst(hash).update(self_type: type).merge(app_subst(hash))
            )
          end
        when AST::Types::Var
          if bound = config.upper_bound(type.name)
            new_config = Config.new(self_type: bound, variable_bounds: config.variable_bounds)
            sub = Substitution.build([], self_type: type)
            # We have to use `self_shape` instead of `raw_shape` here.
            # Keep the `self` types included in the `bound`'s shape, and replace it to the type variable.
            self_shape(bound, new_config)&.subst(sub, type: type)
          end
        when AST::Types::Nil
          subst = class_subst(AST::Builtin::NilClass.instance_type).update(self_type: type)
          object_shape(AST::Builtin::NilClass.module_name).subst(subst, type: type)
        when AST::Types::Logic::Base
          true_shape =
            (object_shape(RBS::BuiltinNames::TrueClass.name)).
              subst(class_subst(AST::Builtin::TrueClass.instance_type).update(self_type: type))
          false_shape =
            (object_shape(RBS::BuiltinNames::FalseClass.name)).
              subst(class_subst(AST::Builtin::FalseClass.instance_type).update(self_type: type))
          union_shape(type, [true_shape, false_shape])
        else
          nil
        end
      end

      def self_shape(type, config)
        case type
        when AST::Types::Self, AST::Types::Instance, AST::Types::Class
          raise
        when AST::Types::Name::Singleton
          singleton_shape(type.name).subst(class_subst(type).update(self_type: nil))
        when AST::Types::Name::Instance
          object_shape(type.name)
            .subst(
              class_subst(type).update(self_type: nil).merge(app_subst(type)),
              type: type
            )
        when AST::Types::Name::Interface
          object_shape(type.name).subst(app_subst(type), type: type)
        when AST::Types::Literal
          instance_type = type.back_type
          subst = class_subst(instance_type).update(self_type: nil)
          object_shape(instance_type.name).subst(subst, type: type)
        when AST::Types::Boolean
          true_shape =
            (object_shape(RBS::BuiltinNames::TrueClass.name)).
              subst(class_subst(AST::Builtin::TrueClass.instance_type).update(self_type: nil))
          false_shape =
            (object_shape(RBS::BuiltinNames::FalseClass.name)).
              subst(class_subst(AST::Builtin::FalseClass.instance_type).update(self_type: nil))
          union_shape(type, [true_shape, false_shape])
        when AST::Types::Proc
          shape = object_shape(AST::Builtin::Proc.module_name).subst(class_subst(AST::Builtin::Proc.instance_type).update(self_type: nil))
          proc_shape(type, shape)
        when AST::Types::Var
          if bound = config.upper_bound(type.name)
            self_shape(bound, config)&.update(type: type)
          end
        else
          raw_shape(type, config)
        end
      end

      def app_subst(type)
        if type.args.empty?
          return Substitution.empty
        end

        vars =
          case type
          when AST::Types::Name::Instance
            entry = factory.env.module_class_entry(type.name, normalized: true) or raise
            entry.primary_decl.type_params.map { _1.name }
          when AST::Types::Name::Interface
            entry = factory.env.interface_decls.fetch(type.name)
            entry.decl.type_params.map { _1.name }
          when AST::Types::Name::Alias
            entry = factory.env.type_alias_decls.fetch(type.name)
            entry.decl.type_params.map { _1.name }
          end

        Substitution.build(vars, type.args)
      end

      def class_subst(type)
        case type
        when AST::Types::Name::Singleton
          self_type = type
          singleton_type = type
          instance_type = factory.instance_type(type.name)
        when AST::Types::Name::Instance
          self_type = type
          singleton_type = type.to_module
          instance_type = factory.instance_type(type.name)
        end

        Substitution.build([], self_type: self_type, module_type: singleton_type, instance_type: instance_type)
      end

      def interface_subst(type)
        Substitution.build([], self_type: type)
      end

      def singleton_shape(type_name)
        singleton_shape_cache[type_name] ||= begin
          shape = Interface::Shape.new(type: AST::Types::Name::Singleton.new(name: type_name), private: true)
          definition = factory.definition_builder.build_singleton(type_name)

          definition.methods.each do |name, method|
            if name == :class
              Steep.logger.tagged(-> { "method = #{type_name}.#{name}" }) do
                overloads = method.defs.map do |type_def|
                  build_method_overload(name, type_def, AST::Builtin::Class.instance_type)
                end

                shape.methods[name] = Interface::Shape::Entry.new(method_name: name, private_method: method.private?, overloads: overloads)
              end
            else
              shape.methods[name] = shared_method_entry(name, method)
            end
          end

          shape
        end
      end

      def object_shape(type_name)
        object_shape_cache[type_name] ||= begin
          shape = Interface::Shape.new(type: AST::Builtin.bottom_type, private: true)

          case
          when type_name.class?
            definition = factory.definition_builder.build_instance(type_name)
          when type_name.interface?
            definition = factory.definition_builder.build_interface(type_name)
          end

          definition or raise

          definition.methods.each do |name, method|
            if name == :class && type_name.class?
              Steep.logger.tagged(-> { "method = #{type_name}##{name}" }) do
                singleton_type = AST::Types::Name::Singleton.new(name: type_name)
                overloads = method.defs.map do |type_def|
                  build_method_overload(name, type_def, singleton_type)
                end

                shape.methods[name] = Interface::Shape::Entry.new(method_name: name, private_method: method.private?, overloads: overloads)
              end
            else
              shape.methods[name] = shared_method_entry(name, method)
            end
          end

          shape
        end
      end

      def shared_method_entry(name, method)
        cache = @method_entry_cache[name] ||= begin
          hash = {} #: Hash[RBS::Definition::Method, Shape::Entry]
          hash.compare_by_identity
        end
        cache[method] ||= begin
          private_method = method.private?
          overloads = method.defs.map do |type_def|
            shared_method_overload(name, type_def)
          end

          indexed_method_entry(name, private_method, overloads)
        end
      end

      def indexed_method_entry(name, private_method, overloads)
        # Methods rebuilt for each definition convert to the same overloads when their type defs
        # are shared, and share one entry through this index. The overloads are shared objects,
        # so the identity of the first one discriminates almost all of the entries.
        index = @method_entry_index[name] ||= {}
        key = overloads[0]&.object_id || 0

        case bucket = index[key]
        when nil
          index[key] = Interface::Shape::Entry.new(method_name: name, private_method: private_method, overloads: overloads)
        when Array
          bucket.find {|entry| same_overloads?(entry, private_method, overloads) } ||
            Interface::Shape::Entry.new(method_name: name, private_method: private_method, overloads: overloads).tap {|entry| bucket << entry }
        else
          if same_overloads?(bucket, private_method, overloads)
            bucket
          else
            Interface::Shape::Entry.new(method_name: name, private_method: private_method, overloads: overloads).tap do |entry|
              index[key] = [bucket, entry]
            end
          end
        end
      end

      def same_overloads?(entry, private_method, overloads)
        return false unless entry.private_method? == private_method

        entry_overloads = entry.overloads
        return false unless entry_overloads.size == overloads.size

        entry_overloads.each_with_index.all? {|overload, index| overload.equal?(overloads[index]) }
      end

      def shared_method_overload(name, type_def)
        cache = @method_overload_cache[name] ||= begin
          hash = {} #: Hash[RBS::Definition::Method::TypeDef, Shape::MethodOverload]
          hash.compare_by_identity
        end
        cache[type_def] ||= indexed_method_overload(name, type_def)
      end

      def indexed_method_overload(name, type_def)
        # Value-equal type defs may be different objects between definitions. They are indexed
        # here by the identity of their type, which discriminates almost all of them, and the
        # remaining components are compared in the bucket.
        index = @method_overload_index[name] ||= {}
        key = type_def.type.object_id

        case bucket = index[key]
        when nil
          index[key] = build_method_overload(name, type_def, nil)
        when Array
          bucket.find {|overload| same_type_def?(overload, type_def) } ||
            build_method_overload(name, type_def, nil).tap {|overload| bucket << overload }
        else
          if same_type_def?(bucket, type_def)
            bucket
          else
            build_method_overload(name, type_def, nil).tap do |overload|
              index[key] = [bucket, overload]
            end
          end
        end
      end

      def same_type_def?(overload, type_def)
        defn = overload.method_defs[0] or return false
        defn.member.equal?(type_def.member) &&
          defn.defined_in == type_def.defined_in &&
          defn.implemented_in == type_def.implemented_in
      end

      def build_method_overload(name, type_def, kernel_class_type)
        method_name = method_name_for(type_def, name)
        method_type = factory.method_type(type_def.type)
        method_type = replace_primitive_method(method_name, type_def, method_type)
        if kernel_class_type
          method_type = replace_kernel_class(method_name, type_def, method_type) { kernel_class_type }
        end
        method_type = add_implicitly_returns_nil(type_def.each_annotation, method_type)
        Shape::MethodOverload.new(method_type, [type_def])
      end

      def union_shape(shape_type, shapes)
        s0, *sx = shapes
        s0 or raise
        all_common_methods = Set.new(s0.methods.each_name)
        sx.each do |shape|
          all_common_methods &= shape.methods.each_name
        end

        shape = Interface::Shape.new(type: shape_type, private: true)
        all_common_methods.each do |method_name|
          overloadss = [] #: Array[Array[Shape::MethodOverload]]
          private_method = false
          shapes.each do |shape|
            entry = shape.methods[method_name] || raise
            overloadss << entry.overloads
            private_method ||= entry.private_method?
          end

          shape.methods[method_name] = Interface::Shape::Entry.new(method_name: method_name, private_method: private_method) do
            overloadss.inject do |overloads1, overloads2|
              # @type break: nil

              types1 = overloads1.map(&:method_type)
              types2 = overloads2.map(&:method_type)

              if types1 == types2
                defs1 = overloads1.flat_map(&:method_defs)
                defs2 = overloads2.flat_map(&:method_defs)

                if defs1 == defs2
                  next overloads1
                end
              end

              method_overloads = {} #: Hash[Shape::MethodOverload, bool]

              overloads1.each do |overload1|
                overloads2.each do |overload2|
                  if overload1.method_type == overload2.method_type
                    overload = Shape::MethodOverload.new(overload1.method_type, overload1.method_defs + overload2.method_defs)
                    method_overloads[overload] = true
                  else
                    if type = MethodType.union(overload1.method_type, overload2.method_type, subtyping)
                      overload = Shape::MethodOverload.new(type, overload1.method_defs + overload2.method_defs)
                      method_overloads[overload] = true
                    end
                  end
                end
              end

              break nil if method_overloads.empty?

              method_overloads.keys
            end
          end
        end

        shape
      end

      def intersection_shape(type, shapes)
        shape = Interface::Shape.new(type: type, private: true)

        shapes.each do |s|
          shape.methods.merge!(s.methods) do |name, old_entry, new_entry|
            if old_entry.public_method? && new_entry.private_method?
              old_entry
            else
              new_entry
            end
          end
        end

        shape
      end

      def method_name_for(type_def, name)
        type_name = type_def.implemented_in || type_def.defined_in

        if name == :new
          case type_def.member
          when RBS::AST::Members::MethodDefinition
            if type_def.member.name == :initialize
              return SingletonMethodName.new(type_name: type_name, method_name: name)
            end
          when RBS::AST::Ruby::Members::DefMember
            if type_def.member.name == :initialize
              return SingletonMethodName.new(type_name: type_name, method_name: name)
            end
          end
        end

        case type_def.member
        when RBS::AST::Members::Base
          case type_def.member.kind
          when :instance
            InstanceMethodName.new(type_name: type_name, method_name: name)
          when :singleton
            SingletonMethodName.new(type_name: type_name, method_name: name)
          when :singleton_instance
            # Assume it a instance method, because `module_function` methods are typically defined with `def`
            InstanceMethodName.new(type_name: type_name, method_name: name)
          else
            raise
          end
        when RBS::AST::Ruby::Members::DefMember, RBS::AST::Ruby::Members::AttributeMember
          InstanceMethodName.new(type_name: type_name, method_name: name)
        end
      end

      def subtyping
        @subtyping ||= Subtyping::Check.new(builder: self)
      end

      def tuple_shape(tuple)
        element_type = AST::Types::Union.build(types: tuple.types)
        array_type = AST::Builtin::Array.instance_type(element_type)

        array_shape = yield(array_type) or raise
        shape = Shape.new(type: tuple, private: true)
        shape.methods.merge!(array_shape.methods)

        aref_entry = array_shape.methods[:[]].yield_self do |aref|
          raise unless aref

          Shape::Entry.new(
            method_name: :[],
            private_method: false,
            overloads: tuple.types.map.with_index {|elem_type, index|
              Shape::MethodOverload.new(
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [AST::Types::Literal.new(value: index)]),
                    return_type: elem_type,
                    location: nil
                  ),
                  block: nil
                ),
                []
              )
            } + aref.overloads
          )
        end

        aref_update_entry = array_shape.methods[:[]=].yield_self do |update|
          raise unless update

          Shape::Entry.new(
            method_name: :[]=,
            private_method: false,
            overloads: tuple.types.map.with_index {|elem_type, index|
              Shape::MethodOverload.new(
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [AST::Types::Literal.new(value: index), elem_type]),
                    return_type: elem_type,
                    location: nil
                  ),
                  block: nil
                ),
                []
              )
            } + update.overloads
          )
        end

        fetch_entry = array_shape.methods[:fetch].yield_self do |fetch|
          raise unless fetch

          Shape::Entry.new(
            method_name: :fetch,
            private_method: false,
            overloads: tuple.types.flat_map.with_index {|elem_type, index|
              [
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [AST::Types::Literal.new(value: index)]),
                    return_type: elem_type,
                    location: nil
                  ),
                  block: nil
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false, default_type: nil)],
                  type: Function.new(
                    params: Function::Params.build(
                      required: [
                        AST::Types::Literal.new(value: index),
                        AST::Types::Var.new(name: :T)
                      ]
                    ),
                    return_type: AST::Types::Union.build(types: [elem_type, AST::Types::Var.new(name: :T)]),
                    location: nil
                  ),
                  block: nil
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false, default_type: nil)],
                  type: Function.new(
                    params: Function::Params.build(required: [AST::Types::Literal.new(value: index)]),
                    return_type: AST::Types::Union.build(types: [elem_type, AST::Types::Var.new(name: :T)]),
                    location: nil
                  ),
                  block: Block.new(
                    type: Function.new(
                      params: Function::Params.build(required: [AST::Builtin::Integer.instance_type]),
                      return_type: AST::Types::Var.new(name: :T),
                      location: nil
                    ),
                    optional: false,
                    self_type: nil
                  )
                )
              ].map { Shape::MethodOverload.new(_1, []) }
            } + fetch.overloads
          )
        end

        first_entry = array_shape.methods[:first].yield_self do |first|
          Shape::Entry.new(
            method_name: :first,
            private_method: false,
            overloads: [
              Shape::MethodOverload.new(
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.empty,
                    return_type: tuple.types[0] || AST::Builtin.nil_type,
                    location: nil
                  ),
                  block: nil
                ),
                []
              )
            ]
          )
        end

        last_entry = array_shape.methods[:last].yield_self do |last|
          Shape::Entry.new(
            method_name: :last,
            private_method: false,
            overloads: [
              Shape::MethodOverload.new(
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.empty,
                    return_type: tuple.types.last || AST::Builtin.nil_type,
                    location: nil
                  ),
                  block: nil
                ),
                []
              )
            ]
          )
        end

        to_ary_entry = Shape::Entry.new(
          method_name: :to_ary,
          private_method: false,
          overloads: [
            Shape::MethodOverload.new(
              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.empty,
                  return_type: tuple,
                  location: nil
                ),
                block: nil
              ),
              []
            )
          ]
        )

        shape.methods[:[]] = aref_entry
        shape.methods[:[]=] = aref_update_entry
        shape.methods[:fetch] = fetch_entry
        shape.methods[:first] = first_entry
        shape.methods[:last] = last_entry
        shape.methods[:to_ary] = to_ary_entry

        shape
      end

      def record_shape(record)
        all_key_type = AST::Types::Union.build(
          types: record.elements.each_key.map {|value| AST::Types::Literal.new(value: value).back_type }
        )
        all_value_type = AST::Types::Union.build(types: record.elements.values)
        hash_type = AST::Builtin::Hash.instance_type(all_key_type, all_value_type)

        hash_shape = yield(hash_type) or raise
        shape = Shape.new(type: record, private: true)
        shape.methods.merge!(hash_shape.methods)

        shape.methods[:[]] = hash_shape.methods[:[]].yield_self do |aref|
          aref or raise
          Shape::Entry.new(
            method_name: :[],
            private_method: false,
            overloads: record.elements.map do |key_value, value_type|
              key_type = AST::Types::Literal.new(value: key_value)

              if record.optional?(key_value)
                value_type = AST::Builtin.optional(value_type)
              end

              Shape::MethodOverload.new(
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type]),
                    return_type: value_type,
                    location: nil
                  ),
                  block: nil
                ),
                []
              )
            end + aref.overloads
          )
        end

        shape.methods[:[]=] = hash_shape.methods[:[]=].yield_self do |update|
          update or raise

          Shape::Entry.new(
            method_name: :[]=,
            private_method: false,
            overloads: record.elements.map do |key_value, value_type|
              key_type = AST::Types::Literal.new(value: key_value)
              Shape::MethodOverload.new(
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type, value_type]),
                    return_type: value_type,
                    location: nil),
                  block: nil
                ),
                []
              )
            end + update.overloads
          )
        end

        shape.methods[:fetch] = hash_shape.methods[:fetch].yield_self do |update|
          update or raise

          Shape::Entry.new(
            method_name: :fetch,
            private_method: false,
            overloads: record.elements.flat_map {|key_value, value_type|
              key_type = AST::Types::Literal.new(value: key_value)

              [
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type]),
                    return_type: value_type,
                    location: nil
                  ),
                  block: nil
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false, default_type: nil)],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type, AST::Types::Var.new(name: :T)]),
                    return_type: AST::Types::Union.build(types: [value_type, AST::Types::Var.new(name: :T)]),
                    location: nil
                  ),
                  block: nil
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false, default_type: nil)],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type]),
                    return_type: AST::Types::Union.build(types: [value_type, AST::Types::Var.new(name: :T)]),
                    location: nil
                  ),
                  block: Block.new(
                    type: Function.new(
                      params: Function::Params.build(required: [all_key_type]),
                      return_type: AST::Types::Var.new(name: :T),
                      location: nil
                    ),
                    optional: false,
                    self_type: nil
                  )
                )
              ].map { Shape::MethodOverload.new(_1, []) }
            } + update.overloads
          )
        end

        shape
      end

      def proc_shape(proc, proc_shape)
        shape = Shape.new(type: proc, private: true)
        shape.methods.merge!(proc_shape.methods)

        overload = Shape::MethodOverload.new(
          MethodType.new(type_params: [], type: proc.type, block: proc.block),
          []
        )

        shape.methods[:[]] = Shape::Entry.new(
          method_name: :[],
          private_method: false,
          overloads: [overload]
        )
        shape.methods[:call] = Shape::Entry.new(
          method_name: :call,
          private_method: false,
          overloads: [overload]
        )

        shape
      end

      def replace_primitive_method(method_name, method_def, method_type)
        defined_in = method_def.defined_in
        member = method_def.member

        if member.is_a?(RBS::AST::Members::MethodDefinition)
          case method_name.method_name
          when :is_a?, :kind_of?, :instance_of?
            case
            when RBS::BuiltinNames::Object.name,
              RBS::BuiltinNames::Kernel.name
              if member.instance?
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::ReceiverIsArg.instance()
                  )
                )
              end
            end

          when :nil?
            case defined_in
            when RBS::BuiltinNames::Object.name,
              AST::Builtin::NilClass.module_name,
              RBS::BuiltinNames::Kernel.name
              if member.instance?
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::ReceiverIsNil.instance()
                  )
                )
              end
            end

          when :!
            case defined_in
            when RBS::BuiltinNames::BasicObject.name,
              RBS::BuiltinNames::TrueClass.name,
              RBS::BuiltinNames::FalseClass.name,
              AST::Builtin::NilClass.module_name
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::Not.instance()
                )
              )
            end

          when :===
            case defined_in
            when RBS::BuiltinNames::Module.name
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ArgIsReceiver.instance()
                )
              )
            when RBS::BuiltinNames::BasicObject.name,
              RBS::BuiltinNames::Object.name,
              RBS::BuiltinNames::Kernel.name,
              RBS::BuiltinNames::String.name,
              RBS::BuiltinNames::Integer.name,
              RBS::BuiltinNames::Symbol.name,
              RBS::BuiltinNames::TrueClass.name,
              RBS::BuiltinNames::FalseClass.name,
              RBS::TypeName.parse("::NilClass")
              # Value based type-case works on literal types which is available for String, Integer, Symbol, TrueClass, FalseClass, and NilClass
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ArgEqualsReceiver.instance()
                )
              )
            end
          when :==
            case defined_in
            when RBS::BuiltinNames::BasicObject.name,
              RBS::BuiltinNames::Object.name,
              RBS::BuiltinNames::Kernel.name,
              RBS::BuiltinNames::String.name,
              RBS::BuiltinNames::Integer.name,
              RBS::BuiltinNames::Symbol.name,
              RBS::BuiltinNames::TrueClass.name,
              RBS::BuiltinNames::FalseClass.name,
              RBS::TypeName.parse("::NilClass")
              # For ==, we use ReceiverIsArg to narrow the receiver based on the argument
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ReceiverIsArg.instance()
                )
              )
            end
          when :<, :<=
            case defined_in
            when RBS::BuiltinNames::Module.name
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ArgIsAncestor.instance()
                )
              )
            end
          end
        end

        method_type
      end

      def replace_kernel_class(method_name, method_def, method_type)
        defined_in = method_def.defined_in
        member = method_def.member

        if member.is_a?(RBS::AST::Members::MethodDefinition)
          case method_name.method_name
          when :class
            case defined_in
            when AST::Builtin::Kernel.module_name
              return method_type.with(type: method_type.type.with(return_type: yield))
            end
          end
        end

        method_type
      end

      def add_implicitly_returns_nil(annotations, method_type)
        return method_type unless implicitly_returns_nil

        if annotations.find { _1.string == "implicitly-returns-nil" }
          return_type = method_type.type.return_type
          method_type = method_type.with(
            type: method_type.type.with(return_type: AST::Types::Union.build(types: [return_type, AST::Builtin.nil_type]))
          )
        else
          method_type
        end
      end
    end
  end
end
