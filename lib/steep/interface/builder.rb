module Steep
  module Interface
    class Builder
      class Config
        attr_reader :self_type, :class_type, :instance_type, :variable_bounds
        attr_reader :resolve_self, :resolve_instance, :resolve_class

        def initialize(self_type:, class_type:, instance_type:, resolve_self: true, resolve_class: true, resolve_instance: true, variable_bounds:)
          @self_type = self_type
          @class_type = class_type
          @instance_type = instance_type
          @resolve_self = resolve_self
          @resolve_class = resolve_class
          @resolve_instance = resolve_instance
          @variable_bounds = variable_bounds
        end

        def update(self_type: self.self_type, class_type: self.class_type, instance_type: self.instance_type, resolve_self: self.resolve_self, resolve_class: self.resolve_class, resolve_instance: self.resolve_instance, variable_bounds: self.variable_bounds)
          _ = self.class.new(
            self_type: self_type,
            class_type: class_type,
            instance_type: instance_type,
            resolve_self: resolve_self,
            resolve_class: resolve_class,
            resolve_instance: resolve_instance,
            variable_bounds: variable_bounds
          )
        end

        def no_resolve
          if resolve?
            @no_resolve ||= update(resolve_self: false, resolve_class: false, resolve_instance: false)
          else
            self
          end
        end

        def resolve?
          resolve_self || resolve_class || resolve_instance
        end

        def ==(other)
          other.is_a?(Config) &&
            other.self_type == self_type &&
            other.class_type == class_type &&
            other.instance_type == instance_type &&
            other.resolve_self == resolve_self &&
            other.resolve_class == resolve_class &&
            other.resolve_instance == resolve_instance &&
            other.variable_bounds == variable_bounds
        end

        alias eql? ==

        def hash
          self_type.hash ^ class_type.hash ^ instance_type.hash ^ resolve_self.hash ^ resolve_class.hash ^ resolve_instance.hash ^ variable_bounds.hash
        end

        def subst
          @subst ||= begin
            Substitution.build(
              [],
              [],
              self_type: self_type,
              module_type: class_type || AST::Types::Class.instance,
              instance_type: instance_type || AST::Types::Instance.instance
            )
          end
        end

        def self_type?
          unless self_type.is_a?(AST::Types::Self)
            self_type
          end
        end

        def instance_type?
          unless instance_type.is_a?(AST::Types::Instance)
            instance_type
          end
        end

        def class_type?
          unless class_type.is_a?(AST::Types::Class)
            class_type
          end
        end
      end

      attr_reader :factory, :cache, :raw_object_cache
      attr_reader :raw_instance_object_shape_cache, :raw_singleton_object_shape_cache, :raw_interface_object_shape_cache

      def initialize(factory)
        @factory = factory
        @cache = {}
        @raw_instance_object_shape_cache = {}
        @raw_singleton_object_shape_cache = {}
        @raw_interface_object_shape_cache = {}
      end

      def include_self?(type)
        case type
        when AST::Types::Self, AST::Types::Instance, AST::Types::Class
          true
        else
          type.each_child.any? {|t| include_self?(t) }
        end
      end

      def fetch_cache(type, public_only, config)
        has_self = include_self?(type)
        fvs = type.free_variables

        # @type var key: cache_key
        key = [
          type,
          public_only,
          has_self ? config.self_type : nil,
          has_self ? config.class_type : nil,
          has_self ? config.instance_type : nil,
          config.resolve_self,
          config.resolve_class,
          config.resolve_instance,
          if config.variable_bounds.each_key.any? {|var| fvs.include?(var)}
            config.variable_bounds.select {|var, _| fvs.include?(var) }
          else
            nil
          end
        ]

        if cache.key?(key)
          cache[key]
        else
          cache[key] = yield
        end
      end

      def shape(type, public_only:, config:)
        fetch_cache(type, public_only, config) do
          case type
          when AST::Types::Self
            if self_type = config.self_type?
              self_type = self_type.subst(config.subst)
              shape(self_type, public_only: public_only, config: config.update(resolve_self: false))
            end
          when AST::Types::Instance
            if instance_type = config.instance_type?
              instance_type = instance_type.subst(config.subst)
              shape(instance_type, public_only: public_only, config: config.update(resolve_instance: false))
            end
          when AST::Types::Class
            if class_type = config.class_type?
              class_type = class_type.subst(config.subst)
              shape(class_type, public_only: public_only, config: config.update(resolve_class: false))
            end
          when AST::Types::Name::Instance, AST::Types::Name::Interface, AST::Types::Name::Singleton
            object_shape(
              type.subst(config.subst),
              public_only,
              !config.resolve_self,
              !config.resolve_instance,
              !config.resolve_class
            )
          when AST::Types::Name::Alias
            if expanded = factory.deep_expand_alias(type)
              shape(expanded, public_only: public_only, config: config)&.update(type: type)
            end
          when AST::Types::Any, AST::Types::Bot, AST::Types::Void, AST::Types::Top
            nil
          when AST::Types::Var
            if bound = config.variable_bounds[type.name]
              shape(bound, public_only: public_only, config: config)&.update(type: type)
            end
          when AST::Types::Union
            if include_self?(type)
              self_var = AST::Types::Var.fresh(:SELF)
              class_var = AST::Types::Var.fresh(:CLASS)
              instance_var = AST::Types::Var.fresh(:INSTANCE)

              bounds = config.variable_bounds.merge({ self_var.name => config.self_type, instance_var.name => config.instance_type, class_var.name => config.class_type })
              type_ = type.subst(Substitution.build([], [], self_type: self_var, instance_type: instance_var, module_type: class_var)) #: AST::Types::Union

              config_ = config.update(resolve_self: false, resolve_class: true, resolve_instance: true, variable_bounds: bounds)

              shapes = type_.types.map do |type|
                shape(type, public_only: public_only, config: config_) or return
              end

              if shape = union_shape(type, shapes, public_only)
                shape.subst(
                  Substitution.build(
                    [self_var.name, class_var.name, instance_var.name],
                    [AST::Types::Self.instance, AST::Types::Class.instance, AST::Types::Instance.instance],
                    self_type: type,
                    instance_type: AST::Builtin.any_type,
                    module_type: AST::Builtin.any_type
                  ),
                  type: type.subst(config.subst)
                )
              end
            else
              config_ = config.update(resolve_self: false)

              shapes = type.types.map do |type|
                shape(type, public_only: public_only, config: config_) or return
              end

              if shape = union_shape(type, shapes, public_only)
                shape.subst(
                  Substitution.build(
                    [], [],
                    self_type: type,
                    instance_type: AST::Builtin.any_type,
                    module_type: AST::Builtin.any_type
                  )
                )
              end
            end
          when AST::Types::Intersection
            self_var = AST::Types::Var.fresh(:SELF)
            class_var = AST::Types::Var.fresh(:CLASS)
            instance_var = AST::Types::Var.fresh(:INSTANCE)

            bounds = config.variable_bounds.merge({ self_var.name => config.self_type, instance_var.name => config.instance_type, class_var.name => config.class_type })
            type_ = type.subst(Substitution.build([], [], self_type: self_var, instance_type: instance_var, module_type: class_var)) #: AST::Types::Intersection

            config_ = config.update(resolve_self: false, resolve_class: true, resolve_instance: true, variable_bounds: bounds)

            shapes = type_.types.map do |type|
              shape(type, public_only: public_only, config: config_) or return
            end

            if shape = intersection_shape(type, shapes, public_only)
              shape.subst(
                Substitution.build(
                  [self_var.name, class_var.name, instance_var.name],
                  [AST::Types::Self.instance, AST::Types::Class.instance, AST::Types::Instance.instance],
                  self_type: type,
                  instance_type: AST::Builtin.any_type,
                  module_type: AST::Builtin.any_type
                ),
                type: type.subst(config.subst)
              )
            end

          when AST::Types::Tuple
            tuple_shape(type, public_only, config)
          when AST::Types::Record
            record_shape(type, public_only, config)
          when AST::Types::Literal
            if shape = shape(type.back_type, public_only: public_only, config: config.update(resolve_self: false))
              shape.subst(Substitution.build([], [], self_type: type), type: type)
            end
          when AST::Types::Boolean, AST::Types::Logic::Base
            shape = union_shape(
              type,
              [
                object_shape(AST::Builtin::TrueClass.instance_type, public_only, true, true, true),
                object_shape(AST::Builtin::FalseClass.instance_type, public_only, true, true, true)
              ],
              public_only
            )

            if shape
              shape.subst(Substitution.build([], [], self_type: type))
            end
          when AST::Types::Nil
            if shape = object_shape(AST::Builtin::NilClass.instance_type, public_only, true, !config.resolve_instance, !config.resolve_class)
              if config.resolve_self
                shape.subst(Substitution.build([], [], self_type: type), type: type)
              else
                shape.update(type: type)
              end
            end
          when AST::Types::Proc
            proc_shape(type, public_only, config)
          else
            raise "Unknown type is given: #{type}"
          end
        end
      end

      def definition_builder
        factory.definition_builder
      end

      def object_shape(type, public_only, keep_self, keep_instance, keep_singleton)
        case type
        when AST::Types::Name::Instance
          definition = definition_builder.build_instance(type.name)
          subst = Interface::Substitution.build(
            definition.type_params,
            type.args,
            self_type: keep_self ? AST::Types::Self.instance : type,
            module_type: keep_singleton ? AST::Types::Class.instance : AST::Types::Name::Singleton.new(name: type.name),
            instance_type: keep_instance ? AST::Types::Instance.instance : factory.instance_type(type.name)
          )
        when AST::Types::Name::Interface
          definition = definition_builder.build_interface(type.name)
          subst = Interface::Substitution.build(
            definition.type_params,
            type.args,
            self_type: keep_self ? AST::Types::Self.instance : type
          )
        when AST::Types::Name::Singleton
          subst = Interface::Substitution.build(
            [],
            [],
            self_type: keep_self ? AST::Types::Self.instance : type,
            module_type: keep_singleton ? AST::Types::Class.instance : AST::Types::Name::Singleton.new(name: type.name),
            instance_type: keep_instance ? AST::Types::Instance.instance : factory.instance_type(type.name)
          )
        end

        raw_object_shape(type, public_only, subst)
      end

      def raw_object_shape(type, public_only, subst)
        cache =
          case type
          when AST::Types::Name::Instance
            raw_instance_object_shape_cache
          when AST::Types::Name::Interface
            raw_interface_object_shape_cache
          when AST::Types::Name::Singleton
            raw_singleton_object_shape_cache
          end

        raw_shape = cache[[type.name, public_only]] ||= begin
          shape = Interface::Shape.new(type: AST::Builtin.bottom_type, private: !public_only)

          case type
          when AST::Types::Name::Instance
            definition = definition_builder.build_instance(type.name)
          when AST::Types::Name::Interface
            definition = definition_builder.build_interface(type.name)
          when AST::Types::Name::Singleton
            definition = definition_builder.build_singleton(type.name)
          end

          definition.methods.each do |name, method|
            next if method.private? && public_only

            Steep.logger.tagged "method = #{type}##{name}" do
              shape.methods[name] = Interface::Shape::Entry.new(
                method_types: method.defs.map do |type_def|
                  method_name = method_name_for(type_def, name)
                  decl = TypeInference::MethodCall::MethodDecl.new(method_name: method_name, method_def: type_def)
                  method_type = factory.method_type(type_def.type, method_decls: Set[decl])
                  replace_primitive_method(method_name, type_def, method_type)
                end
              )
            end
          end

          shape
        end

        raw_shape.subst(subst, type: type)
      end

      def method_name_for(type_def, name)
        type_name = type_def.implemented_in || type_def.defined_in

        if name == :new && type_def.member.is_a?(RBS::AST::Members::MethodDefinition) && type_def.member.name == :initialize
          return SingletonMethodName.new(type_name: type_name, method_name: name)
        end

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
      end

      def subtyping
        @subtyping ||= Subtyping::Check.new(builder: self)
      end

      def union_shape(shape_type, shapes, public_only)
        shapes.inject do |shape1, shape2|
          Interface::Shape.new(type: shape_type, private: !public_only).tap do |shape|
            common_methods = Set.new(shape1.methods.each_name) & Set.new(shape2.methods.each_name)
            common_methods.each do |name|
              Steep.logger.tagged(name.to_s) do
                types1 = shape1.methods[name]&.method_types or raise
                types2 = shape2.methods[name]&.method_types or raise

                if types1 == types2 && types1.map {|type| type.method_decls.to_a }.to_set == types2.map {|type| type.method_decls.to_a }.to_set
                  shape.methods[name] = (shape1.methods[name] or raise)
                else
                  method_types = {} #: Hash[MethodType, true]

                  types1.each do |type1|
                    types2.each do |type2|
                      if type1 == type2
                        method_types[type1.with(method_decls: type1.method_decls + type2.method_decls)] = true
                      else
                        if type = MethodType.union(type1, type2, subtyping)
                          method_types[type] = true
                        end
                      end
                    end
                  end

                  unless method_types.empty?
                    shape.methods[name] = Interface::Shape::Entry.new(method_types: method_types.keys)
                  end
                end
              end
            end
          end
        end
      end

      def intersection_shape(type, shapes, public_only)
        shapes.inject do |shape1, shape2|
          Interface::Shape.new(type: type, private: !public_only).tap do |shape|
            shape.methods.merge!(shape1.methods)
            shape.methods.merge!(shape2.methods)
          end
        end
      end

      def tuple_shape(tuple, public_only, config)
        element_type = AST::Types::Union.build(types: tuple.types, location: nil)
        array_type = AST::Builtin::Array.instance_type(element_type)

        array_shape = shape(array_type, public_only: public_only, config: config.no_resolve) or raise
        shape = Shape.new(type: tuple, private: !public_only)
        shape.methods.merge!(array_shape.methods)

        aref_entry = array_shape.methods[:[]].yield_self do |aref|
          raise unless aref

          Shape::Entry.new(
            method_types: tuple.types.map.with_index {|elem_type, index|
              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.build(required: [AST::Types::Literal.new(value: index)]),
                  return_type: elem_type,
                  location: nil
                ),
                block: nil,
                method_decls: Set[]
              )
            } + aref.method_types
          )
        end

        aref_update_entry = array_shape.methods[:[]=].yield_self do |update|
          raise unless update

          Shape::Entry.new(
            method_types: tuple.types.map.with_index {|elem_type, index|
              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.build(required: [AST::Types::Literal.new(value: index), elem_type]),
                  return_type: elem_type,
                  location: nil
                ),
                block: nil,
                method_decls: Set[]
              )
            } + update.method_types
          )
        end

        fetch_entry = array_shape.methods[:fetch].yield_self do |fetch|
          raise unless fetch

          Shape::Entry.new(
            method_types: tuple.types.flat_map.with_index {|elem_type, index|
              [
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [AST::Types::Literal.new(value: index)]),
                    return_type: elem_type,
                    location: nil
                  ),
                  block: nil,
                  method_decls: Set[]
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false)],
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
                  block: nil,
                  method_decls: Set[]
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false)],
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
                  ),
                  method_decls: Set[]
                )
              ]
            } + fetch.method_types
          )
        end

        first_entry = array_shape.methods[:first].yield_self do |first|
          Shape::Entry.new(
            method_types: [
              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.empty,
                  return_type: tuple.types[0] || AST::Builtin.nil_type,
                  location: nil
                ),
                block: nil,
                method_decls: Set[]
              )
            ]
          )
        end

        last_entry = array_shape.methods[:last].yield_self do |last|
          Shape::Entry.new(
            method_types: [
              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.empty,
                  return_type: tuple.types.last || AST::Builtin.nil_type,
                  location: nil
                ),
                block: nil,
                method_decls: Set[]
              )
            ]
          )
        end

        shape.methods[:[]] = aref_entry
        shape.methods[:[]=] = aref_update_entry
        shape.methods[:fetch] = fetch_entry
        shape.methods[:first] = first_entry
        shape.methods[:last] = last_entry

        shape.subst(
          Substitution.build(
            [], [],
            self_type: config.resolve_self ? tuple : AST::Types::Self.instance,
            instance_type: AST::Builtin::Array.instance_type(fill_untyped: true),
            module_type: AST::Builtin::Array.module_type
          )
        )
      end

      def record_shape(record, public_only, config)
        all_key_type = AST::Types::Union.build(
          types: record.elements.each_key.map {|value| AST::Types::Literal.new(value: value, location: nil) },
          location: nil
        )
        all_value_type = AST::Types::Union.build(types: record.elements.values, location: nil)
        hash_type = AST::Builtin::Hash.instance_type(all_key_type, all_value_type)

        hash_shape = shape(hash_type, public_only: public_only, config: config.no_resolve) or raise
        shape = Shape.new(type: record, private: !public_only)
        shape.methods.merge!(hash_shape.methods)

        shape.methods[:[]] = hash_shape.methods[:[]].yield_self do |aref|
          aref or raise
          Shape::Entry.new(
            method_types: record.elements.map do |key_value, value_type|
              key_type = AST::Types::Literal.new(value: key_value, location: nil)

              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.build(required: [key_type]),
                  return_type: value_type,
                  location: nil
                ),
                block: nil,
                method_decls: Set[]
              )
            end + aref.method_types
          )
        end

        shape.methods[:[]=] = hash_shape.methods[:[]=].yield_self do |update|
          update or raise

          Shape::Entry.new(
            method_types: record.elements.map do |key_value, value_type|
              key_type = AST::Types::Literal.new(value: key_value, location: nil)
              MethodType.new(
                type_params: [],
                type: Function.new(
                  params: Function::Params.build(required: [key_type, value_type]),
                  return_type: value_type,
                  location: nil),
                block: nil,
                method_decls: Set[]
              )
            end + update.method_types
          )
        end

        shape.methods[:fetch] = hash_shape.methods[:fetch].yield_self do |update|
          update or raise

          Shape::Entry.new(
            method_types: record.elements.flat_map {|key_value, value_type|
              key_type = AST::Types::Literal.new(value: key_value, location: nil)

              [
                MethodType.new(
                  type_params: [],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type]),
                    return_type: value_type,
                    location: nil
                  ),
                  block: nil,
                  method_decls: Set[]
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false)],
                  type: Function.new(
                    params: Function::Params.build(required: [key_type, AST::Types::Var.new(name: :T)]),
                    return_type: AST::Types::Union.build(types: [value_type, AST::Types::Var.new(name: :T)]),
                    location: nil
                  ),
                  block: nil,
                  method_decls: Set[]
                ),
                MethodType.new(
                  type_params: [TypeParam.new(name: :T, upper_bound: nil, variance: :invariant, unchecked: false)],
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
                  ),
                  method_decls: Set[]
                )
              ]
            } + update.method_types
          )
        end

        shape.subst(
          Substitution.build(
            [], [],
            self_type: config.resolve_self ? record : AST::Types::Self.instance,
            instance_type: AST::Builtin::Hash.instance_type(fill_untyped: true),
            module_type: AST::Builtin::Hash.module_type
          )
        )
      end

      def proc_shape(proc, public_only, config)
        proc_shape = shape(AST::Builtin::Proc.instance_type, public_only: public_only, config: config.no_resolve) or raise

        shape = Shape.new(type: proc, private: !public_only)
        shape.methods.merge!(proc_shape.methods)

        shape.methods[:[]] = shape.methods[:call] = Shape::Entry.new(
          method_types: [MethodType.new(type_params: [], type: proc.type, block: proc.block, method_decls: Set[])]
        )

        shape.subst(
          Substitution.build(
            [], [],
            self_type: config.resolve_self ? proc : AST::Types::Self.instance,
            instance_type: AST::Builtin::Proc.instance_type(fill_untyped: true),
            module_type: AST::Builtin::Proc.module_type
          )
        )
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
                    return_type: AST::Types::Logic::ReceiverIsArg.new(location: method_type.type.return_type.location)
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
                    return_type: AST::Types::Logic::ReceiverIsNil.new(location: method_type.type.return_type.location)
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
                  return_type: AST::Types::Logic::Not.new(location: method_type.type.return_type.location)
                )
              )
            end

          when :===
            case defined_in
            when RBS::BuiltinNames::Module.name
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ArgIsReceiver.new(location: method_type.type.return_type.location)
                )
              )
            when RBS::BuiltinNames::Object.name,
              RBS::BuiltinNames::Kernel.name,
              RBS::BuiltinNames::String.name,
              RBS::BuiltinNames::Integer.name,
              RBS::BuiltinNames::Symbol.name,
              RBS::BuiltinNames::TrueClass.name,
              RBS::BuiltinNames::FalseClass.name,
              TypeName("::NilClass")
              # Value based type-case works on literal types which is available for String, Integer, Symbol, TrueClass, FalseClass, and NilClass
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ArgEqualsReceiver.new(location: method_type.type.return_type.location)
                )
              )
            end
          when :<, :<=
            case defined_in
            when RBS::BuiltinNames::Module.name
              return method_type.with(
                type: method_type.type.with(
                  return_type: AST::Types::Logic::ArgIsAncestor.new(location: method_type.type.return_type.location)
                )
              )
            end
          end
        end

        method_type
      end
    end
  end
end

