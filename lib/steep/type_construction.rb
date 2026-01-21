module Steep
  class TypeConstruction
    class Pair
      attr_reader :type
      attr_reader :constr

      def initialize(type:, constr:)
        @type = type
        @constr = constr
      end

      def with(type: self.type, constr: self.constr)
        self.class.new(type: type, constr: constr)
      end

      def +(other)
        if type.is_a?(AST::Types::Bot)
          other.with(type: type)
        else
          other
        end
      end

      def context
        constr.context
      end

      def to_ary
        [type, constr, context]
      end
    end

    include NodeHelper

    def inspect
      s = "#<%s:%#018x " % [self.class, object_id]
      s + ">"
    end

    SPECIAL_LVAR_NAMES = Set[:_, :__any__, :__skip__]

    include ModuleHelper

    attr_reader :checker
    attr_reader :source
    attr_reader :annotations
    attr_reader :typing

    attr_reader :context

    def module_context
      context.module_context
    end

    def method_context
      context.method_context
    end

    def method_context!
      method_context or raise
    end

    def block_context
      context.block_context
    end

    def block_context!
      block_context or raise
    end

    def break_context
      context.break_context
    end

    def self_type
      context.self_type
    end

    def variable_context
      context.variable_context
    end

    def initialize(checker:, source:, annotations:, typing:, context:)
      @checker = checker
      @source = source
      @annotations = annotations
      @typing = typing
      @context = context
    end

    def with_new_typing(typing)
      self.class.new(
        checker: checker,
        source: source,
        annotations: annotations,
        typing: typing,
        context: context
      )
    end

    def with_updated_context(type_env: self.context.type_env)
      unless type_env.equal?(self.context.type_env)
        with(context: self.context.with(type_env: type_env))
      else
        self
      end
    end

    def with(annotations: self.annotations, context: self.context, typing: self.typing)
      if context != self.context || typing != self.typing
        self.class.new(
          checker: checker,
          source: source,
          annotations: annotations,
          typing: typing,
          context: context
        )
      else
        self
      end
    end

    def update_context()
      with(context: yield(self.context))
    end

    def update_type_env
      with_updated_context(type_env: yield(context.type_env))
    end

    def check_relation(sub_type:, super_type:, constraints: Subtyping::Constraints.empty)
      Steep.logger.debug { "check_relation: self:#{self_type}, instance:#{module_context.instance_type}, class:#{module_context.module_type} |- #{sub_type} <: #{super_type}" }
      relation = Subtyping::Relation.new(sub_type: sub_type, super_type: super_type)
      checker.push_variable_bounds(variable_context.upper_bounds) do
        checker.check(
          relation,
          self_type: self_type,
          instance_type: module_context.instance_type,
          class_type: module_context.module_type,
          constraints: constraints
        )
      end
    end

    def no_subtyping?(sub_type:, super_type:, constraints: Subtyping::Constraints.empty)
      result = check_relation(sub_type: sub_type, super_type: super_type, constraints: constraints)
      if result.failure?
        result
      end
    end

    def for_new_method(method_name, node, args:, self_type:, definition:)
      annots = source.annotations(block: node, factory: checker.factory, context: nesting)
      definition_method_type = if definition
                                 definition.methods[method_name]&.yield_self do |method|
                                   method.method_types
                                     .map {|method_type| checker.factory.method_type(method_type) }
                                     .inject {|t1, t2| t1 + t2}
                                 end
                               end
      annotation_method_type = annotations.method_type(method_name)

      method_type = annotation_method_type || definition_method_type

      unless method_type
        if definition
          typing.add_error(
            Diagnostic::Ruby::UndeclaredMethodDefinition.new(method_name: method_name, type_name: definition.type_name, node: node)
          )
        else
          typing.add_error(
            Diagnostic::Ruby::MethodDefinitionInUndeclaredModule.new(method_name: method_name, node: node)
          )
        end
      end

      if (annotation_return_type = annots&.return_type) && (method_type_return_type = method_type&.type&.return_type)
        check_relation(sub_type: annotation_return_type, super_type: method_type_return_type).else do |result|
          typing.add_error(
            Diagnostic::Ruby::MethodReturnTypeAnnotationMismatch.new(
              node: node,
              method_type: method_type.type.return_type,
              annotation_type: annots.return_type,
              result: result
            )
          )
        end
      end

      # constructor_method = method&.attributes&.include?(:constructor)

      super_method = if definition
                       if (this_method = definition.methods[method_name])
                         if module_context&.class_name == this_method.defined_in
                           this_method.super_method
                         else
                           this_method
                         end
                       end
                     end

      if definition && method_type
        variable_context = TypeInference::Context::TypeVariableContext.new(method_type.type_params, parent_context: self.variable_context)
      else
        variable_context = self.variable_context
      end

      method_params =
        if method_type
          TypeInference::MethodParams.build(node: node, method_type: method_type)
        else
          TypeInference::MethodParams.empty(node: node)
        end

      method_context = TypeInference::Context::MethodContext.new(
        name: method_name,
        method: definition && definition.methods[method_name],
        method_type: method_type,
        return_type: annots.return_type || method_type&.type&.return_type || AST::Builtin.any_type,
        super_method: super_method,
        forward_arg_type: method_params.forward_arg_type
      )

      local_variable_types = method_params.each_param.with_object({}) do |param, hash| #$ Hash[Symbol, AST::Types::t]
        if param.name
          unless SPECIAL_LVAR_NAMES.include?(param.name)
            hash[param.name] = param.var_type
          end
        end
      end
      type_env = context.type_env.assign_local_variables(local_variable_types)

      type_env = TypeInference::TypeEnvBuilder.new(
        TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annots).merge!.on_duplicate! do |name, original, annotated|
          if method_params.param?(name)
            param = method_params[name]
            if result = no_subtyping?(sub_type: original, super_type: annotated)
              typing.add_error Diagnostic::Ruby::IncompatibleAnnotation.new(
                node: param.node,
                var_name: name,
                result: result,
                relation: result.relation
              )
            end
          end
        end,
        TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableDefinition.new(definition, checker.factory),
        TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableAnnotations.new(annots).merge!
      ).build(type_env)

      method_params.errors.each do |error|
        typing.add_error error
      end

      call_context = case self_type
                     when nil
                       TypeInference::MethodCall::UnknownContext.new()
                     when AST::Types::Name::Singleton
                       TypeInference::MethodCall::MethodContext.new(
                         method_name: SingletonMethodName.new(type_name: module_context.class_name, method_name: method_name)
                       )
                     when AST::Types::Name::Instance, AST::Types::Intersection
                       TypeInference::MethodCall::MethodContext.new(
                         method_name: InstanceMethodName.new(type_name: module_context.class_name, method_name: method_name)
                       )
                     else
                       raise "Unexpected self_type: #{self_type}"
                     end

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        context: TypeInference::Context.new(
          method_context: method_context,
          module_context: module_context,
          block_context: nil,
          break_context: nil,
          self_type: annots.self_type || self_type,
          type_env: type_env,
          call_context: call_context,
          variable_context: variable_context
        ),
        typing: typing,
      )
    end

    def with_method_constr(method_name, node, args:, self_type:, definition:)
      constr = for_new_method(method_name, node, args: args, self_type: self_type, definition: definition)
      constr.checker.push_variable_bounds(constr.variable_context.upper_bounds) do
        yield constr
      end
    end

    def implement_module(module_name:, super_name: nil, annotations:)
      if (annotation = annotations.implement_module_annotation)
        absolute_name(annotation.name.name).yield_self do |absolute_name|
          if checker.factory.class_name?(absolute_name) || checker.factory.module_name?(absolute_name)
            AST::Annotation::Implements::Module.new(
              name: absolute_name,
              args: annotation.name.args
            )
          else
            Steep.logger.error "Unknown class name given to @implements: #{annotation.name.name}"
            nil
          end
        end
      else
        name = module_name || super_name

        if name && checker.factory.env.module_name?(name)
          definition = checker.factory.definition_builder.build_instance(name)

          AST::Annotation::Implements::Module.new(
            name: name,
            args: definition.type_params
          )
        end
      end
    end

    def default_module_context(implement_module_name, nesting:)
      if implement_module_name
        module_name = checker.factory.absolute_type_name(implement_module_name.name, context: nesting) or raise
        module_args = implement_module_name.args.map {|name| AST::Types::Var.new(name: name) }

        instance_def = checker.factory.definition_builder.build_instance(module_name)
        module_def = checker.factory.definition_builder.build_singleton(module_name)

        instance_type = AST::Types::Name::Instance.new(name: module_name, args: module_args)
        module_type = AST::Types::Name::Singleton.new(name: module_name)

        TypeInference::Context::ModuleContext.new(
          instance_type: instance_type,
          module_type: module_type,
          implement_name: implement_module_name,
          nesting: nesting,
          class_name: module_name,
          instance_definition: instance_def,
          module_definition: module_def
        )
      else
        TypeInference::Context::ModuleContext.new(
          instance_type: AST::Builtin::Object.instance_type,
          module_type: AST::Builtin::Object.module_type,
          implement_name: nil,
          nesting: nesting,
          class_name: self.module_context.class_name,
          module_definition: nil,
          instance_definition: nil
        )
      end
    end

    def for_module(node, new_module_name)
      new_nesting = [nesting, new_module_name || false] #: RBS::Resolver::context

      annots = source.annotations(block: node, factory: checker.factory, context: new_nesting)

      implement_module_name = implement_module(module_name: new_module_name, annotations: annots)
      module_context = default_module_context(implement_module_name, nesting: new_nesting)

      unless implement_module_name
        module_context = module_context.update(
          module_type: AST::Builtin::Module.instance_type,
          instance_type: AST::Builtin::BasicObject.instance_type
        )
      end

      if implement_module_name
        module_entry = checker.factory.definition_builder.env.normalized_module_entry(implement_module_name.name)
        if module_entry
          module_context = module_context.update(
            instance_type: AST::Types::Intersection.build(
              types: [
                AST::Builtin::Object.instance_type,
                *module_entry.self_types.map {|module_self|
                  type = case
                        when module_self.name.interface?
                          RBS::Types::Interface.new(
                            name: module_self.name,
                            args: module_self.args,
                            location: module_self.location
                          )
                        when module_self.name.class?
                          RBS::Types::ClassInstance.new(
                            name: module_self.name,
                            args: module_self.args,
                            location: module_self.location
                          )
                        else
                          raise
                        end
                  checker.factory.type(type)
                },
                module_context.instance_type
              ].compact
            )
          )
        elsif checker.factory.definition_builder.env.normalized_class_entry(implement_module_name.name)
          typing.add_error(
            Diagnostic::Ruby::ClassModuleMismatch.new(node: node, name: new_module_name)
          )
        end
      end

      if annots.instance_type
        module_context = module_context.update(instance_type: annots.instance_type)
      end

      if annots.module_type
        module_context = module_context.update(module_type: annots.module_type)
      end

      if annots.self_type
        module_context = module_context.update(module_type: annots.self_type)
      end

      if implement_module_name
        definition = checker.factory.definition_builder.build_instance(implement_module_name.name)
        type_params = definition.type_params_decl.map do |param|
          Interface::TypeParam.new(
            name: param.name,
            upper_bound: checker.factory.type_opt(param.upper_bound_type),
            variance: param.variance,
            unchecked: param.unchecked?,
            default_type: checker.factory.type_opt(param.default_type)
          )
        end
        variable_context = TypeInference::Context::TypeVariableContext.new(type_params)
      else
        variable_context = TypeInference::Context::TypeVariableContext.empty
      end

      module_const_env = TypeInference::ConstantEnv.new(
        factory: checker.factory,
        context: new_nesting,
        resolver: context.type_env.constant_env.resolver
      )

      module_type_env = TypeInference::TypeEnvBuilder.new(
        TypeInference::TypeEnvBuilder::Command::ImportGlobalDeclarations.new(checker.factory),
        TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annots),
        TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableDefinition.new(module_context.module_definition, checker.factory),
        TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableAnnotations.new(annots).merge!,
        TypeInference::TypeEnvBuilder::Command::ImportConstantAnnotations.new(annots)
      ).build(TypeInference::TypeEnv.new(module_const_env))

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        typing: typing,
        context: TypeInference::Context.new(
          method_context: nil,
          block_context: nil,
          break_context: nil,
          module_context: module_context,
          self_type: module_context.module_type,
          type_env: module_type_env,
          call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context.class_name),
          variable_context: variable_context
        )
      )
    end

    def with_module_constr(node, module_name)
      constr = for_module(node, module_name)
      constr.checker.push_variable_bounds(constr.variable_context.upper_bounds) do
        yield constr
      end
    end

    def for_class(node, new_class_name, super_class_name)
      new_nesting = [nesting, new_class_name || false] #: RBS::Resolver::context
      annots = source.annotations(block: node, factory: checker.factory, context: new_nesting)

      class_const_env = TypeInference::ConstantEnv.new(
        factory: checker.factory,
        context: new_nesting,
        resolver: context.type_env.constant_env.resolver
      )

      implement_module_name = implement_module(module_name: new_class_name, super_name: super_class_name, annotations: annots)
      module_context = default_module_context(implement_module_name, nesting: new_nesting)

      if implement_module_name
        if super_class_name && implement_module_name.name == absolute_name(super_class_name)
          module_context = module_context.update(instance_definition: nil, module_definition: nil)
        end

        if !checker.factory.definition_builder.env.normalized_class_entry(implement_module_name.name) &&
          checker.factory.definition_builder.env.normalized_module_entry(implement_module_name.name)
          typing.add_error(
            Diagnostic::Ruby::ClassModuleMismatch.new(node: node, name: new_class_name)
          )
        end
      else
        module_context = module_context.update(
          instance_type: AST::Builtin::Object.instance_type,
          module_type: AST::Builtin::Object.module_type
        )
      end

      if annots.instance_type
        module_context = module_context.update(instance_type: annots.instance_type)
      end

      if annots.module_type
        module_context = module_context.update(module_type: annots.module_type)
      end

      if annots.self_type
        module_context = module_context.update(module_type: annots.self_type)
      end

      definition = checker.factory.definition_builder.build_instance(module_context.class_name)
      type_params = definition.type_params_decl.map do |type_param|
        Interface::TypeParam.new(
          name: type_param.name,
          upper_bound: type_param.upper_bound_type&.yield_self {|t| checker.factory.type(t) },
          variance: type_param.variance,
          unchecked: type_param.unchecked?,
          location: type_param.location,
          default_type: checker.factory.type_opt(type_param.default_type)
        )
      end
      variable_context = TypeInference::Context::TypeVariableContext.new(type_params)

      singleton_definition = checker.factory.definition_builder.build_singleton(module_context.class_name)
      class_type_env = TypeInference::TypeEnvBuilder.new(
        TypeInference::TypeEnvBuilder::Command::ImportGlobalDeclarations.new(checker.factory),
        TypeInference::TypeEnvBuilder::Command::ImportConstantAnnotations.new(annots),
        TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annots),
        TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableDefinition.new(singleton_definition, checker.factory),
      ).build(TypeInference::TypeEnv.new(class_const_env))

      class_body_context = TypeInference::Context.new(
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: module_context.module_type,
        type_env: class_type_env,
        call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context.class_name),
        variable_context: variable_context
      )

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        typing: typing,
        context: class_body_context
      )
    end

    def with_class_constr(node, new_class_name, super_class_name)
      constr = for_class(node, new_class_name, super_class_name)

      constr.checker.push_variable_bounds(constr.variable_context.upper_bounds) do
        yield constr
      end
    end

    def with_sclass_constr(node, type)
      if constr = for_sclass(node, type)
        constr.checker.push_variable_bounds(constr.variable_context.upper_bounds) do
          yield constr
        end
      else
        yield nil
      end
    end

    def meta_type(type)
      case type
      when AST::Types::Name::Instance
        type.to_module
      when AST::Types::Name::Singleton
        AST::Builtin::Class.instance_type
      end
    end

    def for_sclass(node, type)
      annots = source.annotations(block: node, factory: checker.factory, context: nesting)

      instance_type = if type.is_a?(AST::Types::Self)
                        context.self_type
                      else
                        type
                      end

      module_type = case instance_type
                    when AST::Types::Name::Singleton
                      type_name = instance_type.name

                      case checker.factory.env.constant_entry(type_name)
                      when RBS::Environment::ModuleEntry, RBS::Environment::ModuleAliasEntry
                        AST::Builtin::Module.instance_type
                      when RBS::Environment::ClassEntry, RBS::Environment::ClassAliasEntry
                        AST::Builtin::Class.instance_type
                      else
                        raise
                      end

                    when AST::Types::Name::Instance
                      instance_type.to_module
                    else
                      return
                    end

      instance_definition = case instance_type
                            when AST::Types::Name::Singleton
                              type_name = instance_type.name
                              checker.factory.definition_builder.build_singleton(type_name)
                            when AST::Types::Name::Instance
                              type_name = instance_type.name
                              checker.factory.definition_builder.build_instance(type_name)
                            else
                              return
                            end

      module_definition = case module_type
                          when AST::Types::Name::Singleton
                            type_name = module_type.name
                            checker.factory.definition_builder.build_singleton(type_name)
                          else
                            nil
                          end

      module_context = TypeInference::Context::ModuleContext.new(
        instance_type: annots.instance_type || instance_type,
        module_type: annots.self_type || annots.module_type || module_type,
        implement_name: nil,
        nesting: nesting,
        class_name: self.module_context.class_name,
        module_definition: module_definition,
        instance_definition: instance_definition
      )

      singleton_definition = checker.factory.definition_builder.build_singleton(module_context.class_name)
      type_env =
        TypeInference::TypeEnvBuilder.new(
          TypeInference::TypeEnvBuilder::Command::ImportGlobalDeclarations.new(checker.factory),
          TypeInference::TypeEnvBuilder::Command::ImportConstantAnnotations.new(annots),
          TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annots),
          TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableDefinition.new(instance_definition, checker.factory)
        ).build(TypeInference::TypeEnv.new(context.type_env.constant_env))

      body_context = TypeInference::Context.new(
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: meta_type(annots.self_type || type) || AST::Builtin::Class.module_type,
        type_env: type_env,
        call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context.class_name),
        variable_context: TypeInference::Context::TypeVariableContext.empty  # Assuming `::Class` and `::Module` don't have type params
      )

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        typing: typing,
        context: body_context
      )
    end

    def for_branch(node, break_context: context.break_context)
      annots = source.annotations(block: node, factory: checker.factory, context: nesting)

      type_env = TypeInference::TypeEnvBuilder.new(
        TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annots).merge!.on_duplicate! do |name, outer_type, annotation_type|
          relation = Subtyping::Relation.new(sub_type: annotation_type, super_type: outer_type)
          if result = no_subtyping?(sub_type: annotation_type, super_type: outer_type)
            typing.add_error(
              Diagnostic::Ruby::IncompatibleAnnotation.new(
                node: node,
                var_name: name,
                relation: relation,
                result: result
              )
            )
          end
        end
      ).build(context.type_env)

      update_context do |context|
        context.with(type_env: type_env, break_context: break_context)
      end
    end

    def add_typing(node, type:, constr: self)
      raise if constr.typing != self.typing

      typing.add_typing(node, type, nil)
      Pair.new(type: type, constr: constr)
    end

    def add_call(call)
      case call
      when TypeInference::MethodCall::NoMethodError
        typing.add_error(call.error)
      when TypeInference::MethodCall::Error
        call.errors.each do |error|
          typing.add_error(error)
        end
      end

      typing.add_typing(call.node, call.return_type, nil)
      typing.add_call(call.node, call)

      Pair.new(type: call.return_type, constr: self)
    end

    def synthesize(node, hint: nil, condition: false)
      Steep.logger.tagged "synthesize:(#{node.location&.yield_self {|loc| loc.expression.to_s.split(/:/, 2).last } || "-"})" do
        Steep.logger.debug node.type
        case node.type
        when :begin, :kwbegin
          yield_self do
            end_pos = node.loc.expression.end_pos

            *mid_nodes, last_node = each_child_node(node).to_a
            if last_node
              pair = mid_nodes.inject(Pair.new(type: AST::Builtin.nil_type, constr: self)) do |pair, node|
                pair.constr.synthesize(node).yield_self {|p| pair + p }.tap do |new_pair|
                  if new_pair.constr.context != pair.constr.context
                    # update context
                    range = node.loc.expression.end_pos..end_pos
                    typing.cursor_context.set(range, new_pair.constr.context)
                  end
                end
              end

              p = pair.constr.synthesize(last_node, hint: hint, condition: condition)
              last_pair = pair + p
              last_pair.constr.add_typing(node, type: last_pair.type, constr: last_pair.constr)
            else
              add_typing(node, type: AST::Builtin.nil_type)
            end
          end

        when :lvasgn
          yield_self do
            name, rhs = node.children

            case name
            when :_, :__any__
              synthesize(rhs, hint: AST::Builtin.any_type).yield_self do |pair|
                add_typing(node, type: AST::Builtin.any_type, constr: pair.constr)
              end
            when :__skip__
              add_typing(node, type: AST::Builtin.any_type)
            else
              if enforced_type = context.type_env.enforced_type(name)
                case
                when !hint
                  hint = enforced_type
                when check_relation(sub_type: enforced_type, super_type: hint).success?
                  # enforced_type is compatible with hint and more specific to hint.
                  # This typically happens when hint is untyped, top, or void.
                  hint = enforced_type
                end
              end

              if rhs
                rhs_type, rhs_constr, rhs_context = synthesize(rhs, hint: hint).to_ary

                constr = rhs_constr.update_type_env do |type_env|
                  var_type = rhs_type

                  if enforced_type = type_env.enforced_type(name)
                    if result = no_subtyping?(sub_type: rhs_type, super_type: enforced_type)
                      typing.add_error(
                        Diagnostic::Ruby::IncompatibleAssignment.new(
                          node: node,
                          lhs_type: enforced_type,
                          rhs_type: rhs_type,
                          result: result
                        )
                      )

                      var_type = enforced_type
                    end

                    if rhs_type.is_a?(AST::Types::Any)
                      var_type = enforced_type
                    end
                  end

                  type_env.assign_local_variable(name, var_type, enforced_type)
                end

                constr.add_typing(node, type: rhs_type)
              else
                add_typing(node, type: enforced_type || AST::Builtin.any_type)
              end
            end
          end

        when :lvar
          yield_self do
            var = node.children[0]

            if SPECIAL_LVAR_NAMES.include?(var)
              add_typing node, type: AST::Builtin.any_type
            else
              if (type = context.type_env[var])
                add_typing node, type: type
              else
                fallback_to_any(node)
              end
            end
          end

        when :ivasgn
          name = node.children[0]
          rhs = node.children[1]

          rhs_type, constr = synthesize(rhs, hint: context.type_env[name])

          constr.ivasgn(node, rhs_type)

        when :ivar
          yield_self do
            name = node.children[0]

            if type = context.type_env[name]
              add_typing(node, type: type)
            else
              fallback_to_any node
            end
          end

        when :match_with_lvasgn
          each_child_node(node) do |child|
            synthesize(child)
          end
          add_typing(node, type: AST::Builtin.any_type)

        when :op_asgn
          yield_self do
            lhs, op, rhs = node.children

            case lhs.type
            when :lvasgn
              var_node = lhs.updated(:lvar)
              send_node = rhs.updated(:send, [var_node, op, rhs])
              new_node = node.updated(:lvasgn, [lhs.children[0], send_node])

              type, constr = synthesize(new_node, hint: hint)

              constr.add_typing(node, type: type)

            when :ivasgn
              var_node = lhs.updated(:ivar)
              send_node = rhs.updated(:send, [var_node, op, rhs])
              new_node = node.updated(:ivasgn, [lhs.children[0], send_node])

              type, constr = synthesize(new_node, hint: hint)

              constr.add_typing(node, type: type)

            when :cvasgn
              var_node = lhs.updated(:cvar)
              send_node = rhs.updated(:send, [var_node, op, rhs])
              new_node = node.updated(:cvasgn, [lhs.children[0], send_node])

              type, constr = synthesize(new_node, hint: hint)

              constr.add_typing(node, type: type)

            when :gvasgn
              var_node = lhs.updated(:gvar)
              send_node = rhs.updated(:send, [var_node, op, rhs])
              new_node = node.updated(:gvasgn, [lhs.children[0], send_node])

              type, constr = synthesize(new_node, hint: hint)

              constr.add_typing(node, type: type)

            when :send
              new_rhs = rhs.updated(:send, [lhs, node.children[1], node.children[2]])
              new_node = lhs.updated(:send, [lhs.children[0], :"#{lhs.children[1]}=", *lhs.children.drop(2), new_rhs])

              type, constr = synthesize(new_node, hint: hint)

              constr.add_typing(node, type: type)

            else
              Steep.logger.error("Unexpected op_asgn lhs: #{lhs.type}")

              _, constr = synthesize(rhs)
              constr.add_typing(node, type: AST::Builtin.any_type)
            end
          end

        when :super
          yield_self do
            if self_type && method_context!.method
              if super_def = method_context!.super_method
                super_method = Interface::Shape::Entry.new(
                  method_name: method_context!.name,
                  private_method: true,
                  overloads: super_def.defs.map {|type_def|
                    type = checker.factory.method_type(type_def.type)
                    Interface::Shape::MethodOverload.new(type, [type_def])
                  }
                )

                call, constr = type_method_call(
                  node,
                  receiver_type: self_type,
                  method_name: method_context!.name || raise("method context must have a name"),
                  method: super_method,
                  arguments: node.children,
                  block_params: nil,
                  block_body: nil,
                  tapp: nil,
                  hint: hint
                )

                if call && constr
                  constr.add_call(call)
                else
                  error = Diagnostic::Ruby::UnresolvedOverloading.new(
                    node: node,
                    receiver_type: self_type,
                    method_name: method_context!.name,
                    method_types: super_method.method_types
                  )
                  call = TypeInference::MethodCall::Error.new(
                    node: node,
                    context: context.call_context,
                    method_name: method_context!.name || raise("method context must have a name"),
                    receiver_type: self_type,
                    errors: [error]
                  )

                  constr = synthesize_children(node)

                  fallback_to_any(node) { error }
                end
              else
                type_check_untyped_args(node.children).fallback_to_any(node) do
                  Diagnostic::Ruby::UnexpectedSuper.new(node: node, method: method_context!.name)
                end
              end
            else
              type_check_untyped_args(node.children).fallback_to_any(node)
            end
          end

        when :def
          yield_self do
            # @type var node: Parser::AST::Node & Parser::AST::_DefNode

            name, args_node, body_node = node.children

            with_method_constr(
              name,
              node,
              args: args_node.children,
              self_type: module_context&.instance_type,
              definition: module_context&.instance_definition
            ) do |new|
              # @type var new: TypeConstruction

              new.typing.cursor_context.set_node_context(node, new.context)
              new.typing.cursor_context.set_body_context(node, new.context)

              new.method_context!.tap do |method_context|
                if method_context.method
                  if owner = method_context.method.implemented_in || method_context.method.defined_in
                    method_name = InstanceMethodName.new(type_name: owner, method_name: name)
                    new.typing.source_index.add_definition(method: method_name, definition: node)
                  end
                end
              end

              new = new.synthesize_children(args_node)

              body_pair = if body_node
                            return_type = expand_alias(new.method_context!.return_type)
                            if !return_type.is_a?(AST::Types::Void)
                              new.check(body_node, return_type) do |_, actual_type, result|
                                if new.method_context!.attribute_setter?
                                  typing.add_error(
                                    Diagnostic::Ruby::SetterBodyTypeMismatch.new(
                                      node: node,
                                      expected: new.method_context!.return_type,
                                      actual: actual_type,
                                      result: result,
                                      method_name: new.method_context!.name
                                    )
                                  )
                                else
                                  typing.add_error(
                                    Diagnostic::Ruby::MethodBodyTypeMismatch.new(
                                      node: node,
                                      expected: new.method_context!.return_type,
                                      actual: actual_type,
                                      result: result
                                    )
                                  )
                                end
                              end
                            else
                              new.synthesize(body_node)
                            end
                          else
                            return_type = expand_alias(new.method_context!.return_type)
                            if !return_type.is_a?(AST::Types::Void)
                              result = check_relation(sub_type: AST::Builtin.nil_type, super_type: return_type)
                              if result.failure?
                                if new.method_context!.attribute_setter?
                                  typing.add_error(
                                    Diagnostic::Ruby::SetterBodyTypeMismatch.new(
                                      node: node,
                                      expected: new.method_context!.return_type,
                                      actual: AST::Builtin.nil_type,
                                      result: result,
                                      method_name: new.method_context!.name
                                    )
                                  )
                                else
                                  typing.add_error(
                                    Diagnostic::Ruby::MethodBodyTypeMismatch.new(
                                      node: node,
                                      expected: new.method_context!.return_type,
                                      actual: AST::Builtin.nil_type,
                                      result: result
                                    )
                                  )
                                end
                              end
                            end

                            Pair.new(type: AST::Builtin.nil_type, constr: new)
                          end

              if body_node
                # Add context to ranges from the end of the method body to the beginning of the `end` keyword
                if node.loc.end
                  # Skip end-less def
                  begin_pos = body_node.loc.expression.end_pos
                  end_pos = node.loc.end.begin_pos
                  typing.cursor_context.set(begin_pos..end_pos, body_pair.context)
                end
              end

              if module_context
                module_context.defined_instance_methods << node.children[0]
              end

              add_typing(node, type: AST::Builtin::Symbol.instance_type)
            end
          end

        when :defs
          synthesize(node.children[0]).type.tap do |self_type|
            self_type = expand_self(self_type)
            definition =
              case self_type
              when AST::Types::Name::Instance
                name = self_type.name
                checker.factory.definition_builder.build_instance(name)
              when AST::Types::Name::Singleton
                name = self_type.name
                checker.factory.definition_builder.build_singleton(name)
              end

            args_node = node.children[2]
            new = for_new_method(
              node.children[1],
              node,
              args: args_node.children,
              self_type: self_type,
              definition: definition
            )
            new.typing.cursor_context.set_node_context(node, new.context)
            new.typing.cursor_context.set_body_context(node, new.context)

            new.method_context!.tap do |method_context|
              if method_context.method
                name_ = node.children[1]

                method_name =
                  case self_type
                  when AST::Types::Name::Instance
                    InstanceMethodName.new(type_name: method_context.method.implemented_in || raise, method_name: name_)
                  when AST::Types::Name::Singleton
                    SingletonMethodName.new(type_name: method_context.method.implemented_in || raise, method_name: name_)
                  end

                new.typing.source_index.add_definition(method: method_name, definition: node)
              end
            end

            new = new.synthesize_children(args_node)

            each_child_node(node.children[2]) do |arg|
              new.synthesize(arg)
            end

            if node.children[3]
              return_type = expand_alias(new.method_context!.return_type)
              if !return_type.is_a?(AST::Types::Void)
                new.check(node.children[3], return_type) do |return_type, actual_type, result|
                  typing.add_error(
                    Diagnostic::Ruby::MethodBodyTypeMismatch.new(
                      node: node,
                      expected: return_type,
                      actual: actual_type,
                      result: result
                    )
                  )
                end
              else
                new.synthesize(node.children[3])
              end
            end
          end

          if node.children[0].type == :self
            module_context.defined_module_methods << node.children[1]
          end

          add_typing(node, type: AST::Builtin::Symbol.instance_type)

        when :return
          yield_self do
            method_return_type =
              if method_context
                expand_alias(method_context.return_type)
              end

            case node.children.size
            when 0
              value_type = AST::Builtin.nil_type
              constr = self
            when 1
              return_value_node = node.children[0]
              value_type, constr = synthesize(return_value_node, hint: method_return_type)
            else
              # It returns an array
              array = node.updated(:array)
              value_type, constr = synthesize(array, hint: method_return_type)
            end

            if method_return_type
              unless method_context.nil? || method_return_type.is_a?(AST::Types::Void)
                result = constr.check_relation(sub_type: value_type, super_type: method_return_type)

                if result.failure?
                  if method_context.attribute_setter?
                    typing.add_error(
                      Diagnostic::Ruby::SetterReturnTypeMismatch.new(
                        node: node,
                        method_name: method_context.name,
                        expected: method_return_type,
                        actual: value_type,
                        result: result
                      )
                    )
                  else
                    typing.add_error(
                      Diagnostic::Ruby::ReturnTypeMismatch.new(
                        node: node,
                        expected: method_return_type,
                        actual: value_type,
                        result: result
                      )
                    )
                  end
                end
              end
            end

            constr.add_typing(node, type: AST::Builtin.bottom_type)
          end

        when :break
          value = node.children[0]

          if break_context
            break_type = break_context.break_type

            if value
              check(value, break_type) do |break_type, actual_type, result|
                typing.add_error(
                  Diagnostic::Ruby::BreakTypeMismatch.new(
                    node: node,
                    expected: break_type,
                    actual: actual_type,
                    result: result
                  )
                )
              end
            else
              unless break_type.is_a?(AST::Types::Bot)
                check_relation(sub_type: AST::Builtin.nil_type, super_type: break_type).else do |result|
                  typing.add_error(
                    Diagnostic::Ruby::ImplicitBreakValueMismatch.new(
                      node: node,
                      jump_type: break_type,
                      result: result
                    )
                  )
                end
              end
            end
          else
            synthesize(value) if value
            typing.add_error Diagnostic::Ruby::UnexpectedJump.new(node: node)
          end

          add_typing(node, type: AST::Builtin.bottom_type)

        when :next
          value = node.children[0]

          if break_context
            if next_type = break_context.next_type
              next_type = deep_expand_alias(next_type) || next_type

              if value
                _, constr = check(value, next_type) do |break_type, actual_type, result|
                  typing.add_error(
                    Diagnostic::Ruby::BreakTypeMismatch.new(
                      node: node,
                      expected: break_type,
                      actual: actual_type,
                      result: result
                    )
                  )
                end
              else
                check_relation(sub_type: AST::Builtin.nil_type, super_type: next_type).else do |result|
                  typing.add_error(
                    Diagnostic::Ruby::BreakTypeMismatch.new(
                      node: node,
                      expected: next_type,
                      actual: AST::Builtin.nil_type,
                      result: result
                    )
                  )
                end
              end
            else
              if value
                synthesize(value)
                typing.add_error Diagnostic::Ruby::UnexpectedJumpValue.new(node: node)
              end
            end
          else
            synthesize(value) if value
            typing.add_error Diagnostic::Ruby::UnexpectedJump.new(node: node)
          end

          add_typing(node, type: AST::Builtin.bottom_type)

        when :retry
          add_typing(node, type: AST::Builtin.bottom_type)

        when :procarg0
          yield_self do
            constr = self #: TypeConstruction

            node.children.each do |arg|
              if arg.is_a?(Symbol)
                if SPECIAL_LVAR_NAMES === arg
                  _, constr = add_typing(node, type: AST::Builtin.any_type)
                else
                  type = context.type_env[arg]

                  if type
                    _, constr = add_typing(node, type: type)
                  else
                    type = AST::Builtin.any_type
                    _, constr = lvasgn(node, type)
                  end
                end
              else
                _, constr = constr.synthesize(arg)
              end
            end

            Pair.new(constr: constr, type: AST::Builtin.any_type)
          end

        when :mlhs
          yield_self do
            constr = self #: TypeConstruction

            node.children.each do |arg|
              _, constr = constr.synthesize(arg)
            end

            Pair.new(constr: constr, type: AST::Builtin.any_type)
          end

        when :arg, :kwarg
          yield_self do
            var = node.children[0]

            if SPECIAL_LVAR_NAMES.include?(var)
              add_typing(node, type: AST::Builtin.any_type)
            else
              type = context.type_env[var]

              if type
                add_typing(node, type: type)
              else
                type = AST::Builtin.any_type
                lvasgn(node, type)
              end
            end
          end

        when :optarg, :kwoptarg
          yield_self do
            var = node.children[0]
            rhs = node.children[1]

            if SPECIAL_LVAR_NAMES.include?(var)
              synthesize(rhs)
              add_typing(node, type: AST::Builtin.any_type)
            else
              var_type = context.type_env[var]

              if var_type
                type, constr = check(rhs, var_type) do |expected_type, actual_type, result|
                  typing.add_error(
                    Diagnostic::Ruby::IncompatibleAssignment.new(
                      node: node,
                      lhs_type: expected_type,
                      rhs_type: actual_type,
                      result: result
                    )
                  )
                end
              else
                type, constr = synthesize(rhs)
              end

              constr.add_typing(node, type: type)
            end
          end

        when :restarg
          yield_self do
            var = node.children[0]

            if !var || SPECIAL_LVAR_NAMES.include?(var)
              return add_typing(node, type: AST::Builtin.any_type)
            end

            type = context.type_env[var]

            unless type
              if context.method_context&.method_type
                Steep.logger.error { "Unknown variable: #{node}" }
              end
              typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
              type = AST::Builtin::Array.instance_type(AST::Builtin.any_type)
            end

            add_typing(node, type: type)
          end

        when :kwrestarg
          yield_self do
            var = node.children[0]

            if !var || SPECIAL_LVAR_NAMES.include?(var)
              return add_typing(node, type: AST::Builtin.any_type)
            end

            type = context.type_env[var]
            unless type
              if context.method_context&.method_type
                Steep.logger.error { "Unknown variable: #{node}" }
              end
              typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
              type = AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type, AST::Builtin.any_type)
            end

            add_typing(node, type: type)
          end

        when :float
          add_typing(node, type: AST::Builtin::Float.instance_type)

        when :rational
          add_typing(node, type: AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::Rational"), args: []))

        when :complex
          add_typing(node, type: AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::Complex"), args: []))

        when :nil
          add_typing(node, type: AST::Builtin.nil_type)

        when :int
          yield_self do
            literal_type = test_literal_type(node.children[0], hint)

            if literal_type
              add_typing(node, type: literal_type)
            else
              add_typing(node, type: AST::Builtin::Integer.instance_type)
            end
          end

        when :sym
          yield_self do
            literal_type = test_literal_type(node.children[0], hint)

            if literal_type
              add_typing(node, type: literal_type)
            else
              add_typing(node, type: AST::Builtin::Symbol.instance_type)
            end
          end

        when :str
          yield_self do
            literal_type = test_literal_type(node.children[0], hint)

            if literal_type
              add_typing(node, type: literal_type)
            else
              add_typing(node, type: AST::Builtin::String.instance_type)
            end
          end

        when :true, :false
          ty = node.type == :true ? AST::Types::Literal.new(value: true) : AST::Types::Literal.new(value: false)

          case
          when hint && check_relation(sub_type: ty, super_type: hint).success? && !hint.is_a?(AST::Types::Any) && !hint.is_a?(AST::Types::Top)
            add_typing(node, type: hint)
          when condition
            add_typing(node, type: ty)
          else
            add_typing(node, type: AST::Types::Boolean.instance)
          end

        when :hash, :kwargs
          # :kwargs happens for method calls with keyword argument, but the method doesn't have keyword params.
          # Conversion from kwargs to hash happens, and this when-clause is to support it.
          type_hash(node, hint: hint).tap do |pair|
            if pair.type == AST::Builtin::Hash.instance_type(fill_untyped: true)
              case hint
              when AST::Types::Any, AST::Types::Top, AST::Types::Void
                # ok
              else
                unless hint == pair.type
                  pair.constr.typing.add_error Diagnostic::Ruby::UnannotatedEmptyCollection.new(node: node)
                end
              end
            end
          end

        when :dstr, :xstr
          each_child_node(node) do |child|
            synthesize(child)
          end

          add_typing(node, type: AST::Builtin::String.instance_type)

        when :dsym
          each_child_node(node) do |child|
            synthesize(child)
          end

          add_typing(node, type: AST::Builtin::Symbol.instance_type)

        when :class
          yield_self do
            constr = self

            # @type var name_node: Parser::AST::Node
            # @type var super_node: Parser::AST::Node?

            name_node, super_node, _ = node.children

            if name_node.type == :const
              _, constr, class_name = synthesize_constant_decl(name_node, name_node.children[0], name_node.children[1]) do
                typing.add_error(
                  Diagnostic::Ruby::UnknownConstant.new(node: name_node, name: name_node.children[1]).class!
                )
              end

              if class_name
                check_deprecation_constant(class_name, name_node, name_node.location.expression)
              end
            else
              _, constr = synthesize(name_node)
            end

            if class_name
              typing.source_index.add_definition(constant: class_name, definition: name_node)
            end

            if super_node
              if super_node.type == :const
                _, constr, super_name = constr.synthesize_constant(super_node, super_node.children[0], super_node.children[1]) do
                  typing.add_error(
                    Diagnostic::Ruby::UnknownConstant.new(node: super_node, name: super_node.children[1]).class!
                  )
                end

                if super_name
                  typing.source_index.add_reference(constant: super_name, ref: super_node)
                end
              else
                _, constr = synthesize(super_node, hint: nil, condition: false)
              end
            end

            with_class_constr(node, class_name, super_name) do |constructor|
              if module_type = constructor.module_context&.module_type
                _, constructor = constructor.add_typing(name_node, type: module_type)
              else
                _, constructor = constructor.fallback_to_any(name_node)
              end

              constructor.typing.cursor_context.set_node_context(node, constructor.context)
              constructor.typing.cursor_context.set_body_context(node, constructor.context)

              constructor.synthesize(node.children[2]) if node.children[2]

              if constructor.module_context&.implement_name && !namespace_module?(node)
                constructor.validate_method_definitions(node, constructor.module_context.implement_name || raise)
              end
            end

            add_typing(node, type: AST::Builtin.nil_type)
          end

        when :module
          yield_self do
            constr = self

            # @type var name_node: Parser::AST::Node
            name_node, _ = node.children

            if name_node.type == :const
              _, constr, module_name = synthesize_constant_decl(name_node, name_node.children[0], name_node.children[1]) do
                typing.add_error Diagnostic::Ruby::UnknownConstant.new(node: name_node, name: name_node.children[1]).module!
              end

              if module_name
                check_deprecation_constant(module_name, name_node, name_node.location.expression)
              end
            else
              _, constr = synthesize(name_node)
            end

            if module_name
              constr.typing.source_index.add_definition(constant: module_name, definition: name_node)
            end

            with_module_constr(node, module_name) do |constructor|
              if module_type = constructor.module_context&.module_type
                _, constructor = constructor.add_typing(name_node, type: module_type)
              else
                _, constructor = constructor.fallback_to_any(name_node)
              end

              constructor.typing.cursor_context.set_node_context(node, constructor.context)
              constructor.typing.cursor_context.set_body_context(node, constructor.context)

              constructor.synthesize(node.children[1]) if node.children[1]

              if constructor.module_context&.implement_name && !namespace_module?(node)
                constructor.validate_method_definitions(node, constructor.module_context.implement_name || raise)
              end
            end

            add_typing(node, type: AST::Builtin.nil_type)
          end

        when :sclass
          yield_self do
            type, constr = synthesize(node.children[0]).to_ary

            with_sclass_constr(node, type) do |constructor|
              unless constructor
                typing.add_error(
                  Diagnostic::Ruby::UnsupportedSyntax.new(
                    node: node,
                    message: "sclass receiver must be instance type or singleton type, but type given `#{type}`"
                  )
                )
                return constr.add_typing(node, type: AST::Builtin.nil_type)
              end

              constructor.typing.cursor_context.set_node_context(node, constructor.context)
              constructor.typing.cursor_context.set_body_context(node, constructor.context)

              constructor.synthesize(node.children[1]) if node.children[1]

              if constructor.module_context.instance_definition && module_context.module_definition
                if constructor.module_context.instance_definition.type_name == module_context.module_definition.type_name
                  module_context.defined_module_methods.merge(constructor.module_context.defined_instance_methods)
                end
              end
            end

            constr.add_typing(node, type: AST::Builtin.nil_type)
          end

        when :self
          add_typing node, type: AST::Types::Self.instance

        when :cbase
          add_typing node, type: AST::Types::Void.instance

        when :const
          yield_self do
            type, constr, name = synthesize_constant(node, node.children[0], node.children[1])

            if name
              typing.source_index.add_reference(constant: name, ref: node)
              constr.check_deprecation_constant(name, node, node.location.expression)
            end

            Pair.new(type: type, constr: constr)
          end

        when :casgn
          yield_self do
            constant_type, constr, constant_name = synthesize_constant_decl(nil, node.children[0], node.children[1]) do
              typing.add_error(
                Diagnostic::Ruby::UnknownConstant.new(
                  node: node,
                  name: node.children[1]
                )
              )
            end

            if constant_name
              typing.source_index.add_definition(constant: constant_name, definition: node)
              location = node.location #: Parser::Source::Map & Parser::AST::_Variable
              constr.check_deprecation_constant(constant_name, node, location.name)
            end

            value_type, constr = constr.synthesize(node.children.last, hint: constant_type)

            result = check_relation(sub_type: value_type, super_type: constant_type)
            if result.failure?
              typing.add_error(
                Diagnostic::Ruby::IncompatibleAssignment.new(
                  node: node,
                  lhs_type: constant_type,
                  rhs_type: value_type,
                  result: result
                )
              )

              constr.add_typing(node, type: constant_type)
            else
              constr.add_typing(node, type: value_type)
            end
          end

        when :yield
          if method_context && method_context.method_type
            if block_type = method_context.block_type
              if block_type.type.params
                type = AST::Types::Proc.new(
                  type: block_type.type,
                  block: nil,
                  self_type: block_type.self_type
                )
                args = TypeInference::SendArgs.new(
                  node: node,
                  arguments: node.children,
                  type: type
                )

                # @type var errors: Array[Diagnostic::Ruby::Base]
                errors = []
                constr = type_check_args(
                  nil,
                  args,
                  Subtyping::Constraints.new(unknowns: []),
                  errors
                )

                errors.each do |error|
                  typing.add_error(error)
                end
              else
                constr = type_check_untyped_args(node.children)
              end

              add_typing(node, type: block_type.type.return_type)
            else
              typing.add_error(Diagnostic::Ruby::UnexpectedYield.new(node: node))
              fallback_to_any node
            end
          else
            fallback_to_any node
          end

        when :zsuper
          yield_self do
            if method_context && method_context.method
              if method_context.super_method
                types = method_context.super_method.method_types.map {|method_type|
                  checker.factory.method_type(method_type).type.return_type
                }
                add_typing(node, type: union_type(*types))
              else
                fallback_to_any(node) do
                  Diagnostic::Ruby::UnexpectedSuper.new(node: node, method: method_context.name)
                end
              end
            else
              fallback_to_any node
            end
          end

        when :array
          yield_self do
            if node.children.empty?
              if hint
                array = AST::Builtin::Array.instance_type(AST::Builtin.any_type)
                if check_relation(sub_type: array, super_type: hint).success?
                  add_typing node, type: hint
                else
                  add_typing node, type: array
                end
              else
                typing.add_error Diagnostic::Ruby::UnannotatedEmptyCollection.new(node: node)
                add_typing node, type: AST::Builtin::Array.instance_type(AST::Builtin.any_type)
              end
            else
              if hint
                tuples = select_flatten_types(hint) {|type| type.is_a?(AST::Types::Tuple) } #: Array[AST::Types::Tuple]
                unless tuples.empty?
                  tuples.each do |tuple|
                    typing.new_child() do |child_typing|
                      if pair = with_new_typing(child_typing).try_tuple_type(node, tuple)
                        return pair.with(constr: pair.constr.save_typing)
                      end
                    end
                  end
                end
              end

              if hint
                arrays = select_flatten_types(hint) {|type| AST::Builtin::Array.instance_type?(type) } #: Array[AST::Types::Name::Instance]
                unless arrays.empty?
                  arrays.each do |array|
                    typing.new_child() do |child_typing|
                      pair = with_new_typing(child_typing).try_array_type(node, array)
                      if pair.constr.check_relation(sub_type: pair.type, super_type: hint).success?
                        return pair.with(constr: pair.constr.save_typing)
                      end
                    end
                  end
                end
              end

              try_array_type(node, nil)
            end
          end

        when :and
          yield_self do
            left_node, right_node = node.children

            left_type, constr, left_context = synthesize(left_node, hint: hint, condition: true).to_ary

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing, config: builder_config)
            left_truthy, left_falsy = interpreter.eval(env: left_context.type_env, node: left_node)

            if left_type.is_a?(AST::Types::Logic::Env)
              left_type = left_type.type
            end

            right_type, constr, right_context =
              constr
                .update_type_env { left_truthy.env }
                .tap {|constr| typing.cursor_context.set_node_context(right_node, constr.context) }
                .for_branch(right_node)
                .synthesize(right_node, hint: hint, condition: true).to_ary

            right_truthy, right_falsy = interpreter.eval(env: right_context.type_env, node: right_node)

            case
            when left_truthy.unreachable
              # Always left_falsy
              env = left_falsy.env
              type = left_falsy.type
            when left_falsy.unreachable
              # Always left_truthy ==> right
              env = right_context.type_env
              type = right_type
            when right_truthy.unreachable && right_falsy.unreachable
              env = left_falsy.env
              type = left_falsy.type
            else
              env = context.type_env.join(left_falsy.env, right_context.type_env)
              type = union_type(left_falsy.type, right_type)

              unless type.is_a?(AST::Types::Any)
                if check_relation(sub_type: type, super_type: AST::Types::Boolean.instance).success?
                  type = AST::Types::Boolean.instance
                end
              end
            end

            if condition
              type = AST::Types::Logic::Env.new(
                truthy: right_truthy.env,
                falsy: context.type_env.join(left_falsy.env, right_falsy.env),
                type: type
              )
            end

            constr.update_type_env { env }.add_typing(node, type: type)
          end

        when :or
          yield_self do
            left_node, right_node = node.children

            if hint
              left_hint = union_type_unify(hint, AST::Builtin.nil_type, AST::Builtin.false_type)
            end
            left_type, constr, left_context = synthesize(left_node, hint: left_hint, condition: true).to_ary

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing, config: builder_config)
            left_truthy, left_falsy = interpreter.eval(env: left_context.type_env, node: left_node)

            if left_type.is_a?(AST::Types::Logic::Env)
              left_type = left_type.type
            end

            right_type, constr, right_context =
              constr
                .update_type_env { left_falsy.env }
                .tap {|constr| typing.cursor_context.set_node_context(right_node, constr.context) }
                .for_branch(right_node)
                .synthesize(right_node, hint: left_truthy.type, condition: true).to_ary

            right_truthy, right_falsy = interpreter.eval(env: right_context.type_env, node: right_node)

            case
            when left_falsy.unreachable
              env = left_truthy.env
              type = left_truthy.type
            when left_truthy.unreachable
              # Always left_falsy ==> right
              env = right_context.type_env
              type = right_type
            when right_truthy.unreachable && right_falsy.unreachable
              env = left_truthy.env
              type = left_truthy.type
            else
              env = context.type_env.join(left_truthy.env, right_context.type_env)
              type = union_type(left_truthy.type, right_type)

              unless type.is_a?(AST::Types::Any)
                if check_relation(sub_type: type, super_type: AST::Types::Boolean.instance).success?
                  type = AST::Types::Boolean.instance
                end
              end
            end

            if condition
              type = AST::Types::Logic::Env.new(
                truthy: context.type_env.join(left_truthy.env, right_truthy.env),
                falsy: right_falsy.env,
                type: type
              )
            end

            constr.update_type_env { env }.add_typing(node, type: type)
          end

        when :if
          yield_self do
            cond, true_clause, false_clause = node.children

            cond_type, constr = synthesize(cond, condition: true).to_ary
            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: constr.typing, config: builder_config)
            truthy, falsy = interpreter.eval(env: constr.context.type_env, node: cond)

            if true_clause
              true_pair =
                constr
                  .update_type_env { truthy.env }
                  .for_branch(true_clause)
                  .tap {|constr| typing.cursor_context.set_node_context(true_clause, constr.context) }
                  .synthesize(true_clause, hint: hint)
            end

            if false_clause
              false_pair =
                constr
                  .update_type_env { falsy.env }
                  .for_branch(false_clause)
                  .tap {|constr| typing.cursor_context.set_node_context(false_clause, constr.context) }
                  .synthesize(false_clause, hint: hint)
            end

            constr = constr.update_type_env do |env|
              envs = [] #: Array[TypeInference::TypeEnv]

              unless truthy.unreachable
                if true_pair
                  unless true_pair.type.is_a?(AST::Types::Bot)
                    envs << true_pair.context.type_env
                  end
                else
                  envs << truthy.env
                end
              end

              if false_pair
                unless falsy.unreachable
                  unless false_pair.type.is_a?(AST::Types::Bot)
                    envs << false_pair.context.type_env
                  end
                end
              else
                envs << falsy.env
              end

              env.join(*envs)
            end

            if truthy.unreachable
              if true_clause
                _, _, _, loc = deconstruct_if_node!(node)

                if loc.respond_to?(:keyword)
                  condition_loc = loc #: NodeHelper::condition_loc
                  case condition_loc.keyword.source
                  when "if", "elsif"
                    location = condition_loc.begin || condition_loc.keyword
                  when "unless"
                    # `else` token always exists
                    location = condition_loc.else || raise
                  end
                else
                  location = true_clause.loc.expression
                end

                typing.add_error(
                  Diagnostic::Ruby::UnreachableBranch.new(
                    node: true_clause,
                    location: location || raise
                  )
                )
              end
            end

            if falsy.unreachable
              if false_clause
                _, _, _, loc = deconstruct_if_node!(node)

                if loc.respond_to?(:keyword)
                  condition_loc = loc #: NodeHelper::condition_loc

                  case condition_loc.keyword.source
                  when "if", "elsif"
                    # `else` token always exists
                    location = condition_loc.else || raise
                  when "unless"
                    location = condition_loc.begin || condition_loc.keyword
                  end
                else
                  location = false_clause.loc.expression
                end

                typing.add_error(
                  Diagnostic::Ruby::UnreachableBranch.new(
                    node: false_clause,
                    location: location || raise
                  )
                )
              end
            end

            node_type = union_type_unify(true_pair&.type || AST::Builtin.nil_type, false_pair&.type || AST::Builtin.nil_type)
            add_typing(node, type: node_type, constr: constr)
          end

        when :case
          yield_self do
            # @type var node: Parser::AST::Node & Parser::AST::_CaseNode

            cond, *whens, els = node.children

            constr = self #: TypeConstruction
            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing, config: builder_config)

            if cond
              types, envs = TypeInference::CaseWhen.type_check(constr, node, interpreter, hint: hint, condition: condition)
            else
              branch_results = [] #: Array[Pair]

              condition_constr = constr

              whens.each do |when_clause|
                when_clause_constr = condition_constr
                body_envs = [] #: Array[TypeInference::TypeEnv]

                # @type var tests: Array[Parser::AST::Node]
                # @type var body: Parser::AST::Node?
                *tests, body = when_clause.children

                branch_reachable = false

                tests.each do |test|
                  test_type, condition_constr = condition_constr.synthesize(test, condition: true)
                  truthy, falsy = interpreter.eval(env: condition_constr.context.type_env, node: test)
                  truthy_env = truthy.env
                  falsy_env = falsy.env

                  condition_constr = condition_constr.update_type_env { falsy_env }
                  body_envs << truthy_env

                  branch_reachable ||= !truthy.unreachable
                end

                branch_result =
                  if body
                    when_clause_constr
                      .update_type_env {|env| env.join(*body_envs) }
                      .for_branch(body)
                      .tap {|constr| typing.cursor_context.set_node_context(body, constr.context) }
                      .synthesize(body, hint: hint)
                  else
                    Pair.new(type: AST::Builtin.nil_type, constr: when_clause_constr)
                  end

                branch_results << branch_result

                unless branch_reachable
                  unless branch_result.type.is_a?(AST::Types::Bot)
                    typing.add_error(
                      Diagnostic::Ruby::UnreachableValueBranch.new(
                        node: when_clause,
                        type: branch_result.type,
                        location: when_clause.location.keyword || raise
                      )
                    )
                  end
                end
              end

              if els
                branch_results << condition_constr.synthesize(els, hint: hint)
              else
                branch_results << Pair.new(type: AST::Builtin.nil_type, constr: condition_constr)
              end

              branch_results.reject! do |result|
                result.type.is_a?(AST::Types::Bot)
              end

              types = branch_results.map(&:type)
              envs = branch_results.map {|result| result.constr.context.type_env }
            end

            constr = constr.update_type_env do |env|
              env.join(*envs)
            end

            add_typing(node, type: union_type_unify(*types), constr: constr)
          end

        when :rescue
          yield_self do
            body, *resbodies, else_node = node.children
            body_pair = synthesize(body, hint: hint) if body

            # @type var body_constr: TypeConstruction
            body_constr = if body_pair
                            update_type_env do |env|
                              env.join(env, body_pair.context.type_env)
                            end
                          else
                            self
                          end

            resbody_pairs = resbodies.map do |resbody|
              # @type var exn_classes: Parser::AST::Node
              # @type var assignment: Parser::AST::Node?
              # @type var body: Parser::AST::Node?
              exn_classes, assignment, body = resbody.children

              if exn_classes
                case exn_classes.type
                when :array
                  exn_types = exn_classes.children.map {|child| synthesize(child).type }
                else
                  Steep.logger.error "Unexpected exception list: #{exn_classes.type}"
                end
              end

              if assignment
                case assignment.type
                when :lvasgn
                  var_name = assignment.children[0]
                else
                  Steep.logger.error "Unexpected rescue variable assignment: #{assignment.type}"
                end
              end

              resbody_construction = body_constr.for_branch(resbody).update_type_env do |env|
                assignments = {} #: Hash[Symbol, AST::Types::t]

                case
                when exn_classes && var_name && exn_types
                  instance_types = exn_types.map do |type|
                    type = expand_alias(type)
                    case
                    when type.is_a?(AST::Types::Name::Singleton)
                      to_instance_type(type)
                    else
                      AST::Builtin.any_type
                    end
                  end

                  assignments[var_name] = AST::Types::Union.build(types: instance_types)
                when var_name
                  assignments[var_name] = AST::Builtin.any_type
                end

                env.assign_local_variables(assignments)
              end

              if body
                resbody_construction.typing.cursor_context.set_node_context(body, resbody_construction.context)
                resbody_construction.synthesize(body, hint: hint)
              else
                Pair.new(constr: body_constr, type: AST::Builtin.nil_type)
              end
            end

            resbody_pairs.select! do |pair|
              no_subtyping?(sub_type: pair.type, super_type: AST::Types::Bot.instance)
            end

            resbody_types = resbody_pairs.map(&:type)
            resbody_envs = resbody_pairs.map {|pair| pair.context.type_env }

            else_constr = body_pair&.constr || self

            if else_node
              else_type, else_constr = else_constr.for_branch(else_node).synthesize(else_node, hint: hint)
              else_constr
                .update_type_env {|env| env.join(*resbody_envs, env) }
                .add_typing(node, type: union_type(else_type, *resbody_types))
            else
              if resbody_types.empty?
                constr = body_pair ? body_pair.constr : self
                constr.add_typing(node, type: body_pair&.type || AST::Builtin.nil_type)
              else
                update_type_env {|env| env.join(*resbody_envs, else_constr.context.type_env) }
                  .add_typing(node, type: union_type(*[body_pair&.type, *resbody_types].compact))
              end
            end
          end

        when :resbody
          yield_self do
            klasses, asgn, body = node.children
            synthesize(klasses) if klasses
            synthesize(asgn) if asgn
            if body
              body_type = synthesize(body, hint: hint).type
              add_typing(node, type: body_type)
            else
              add_typing(node, type: AST::Builtin.nil_type)
            end
          end

        when :ensure
          yield_self do
            body, ensure_body = node.children
            body_type = synthesize(body).type if body
            synthesize(ensure_body) if ensure_body
            if body_type
              add_typing(node, type: body_type)
            else
              add_typing(node, type: AST::Builtin.nil_type)
            end
          end

        when :masgn
          type_masgn(node)

        when :for
          yield_self do
            asgn, collection, body = node.children

            collection_type, constr, collection_context = synthesize(collection).to_ary
            collection_type = expand_self(collection_type)

            if collection_type.is_a?(AST::Types::Any)
              var_type = AST::Builtin.any_type
            else
              if each = calculate_interface(collection_type, :each, private: true)
                method_type = (each.method_types || []).find do |type|
                  if type.block
                    if type.block.type.params
                      type.block.type.params.first_param
                    else
                      true
                    end
                  end
                end
                if method_type
                  if block = method_type.block
                    if first_param = block.type&.params&.first_param
                      var_type = first_param.type #: AST::Types::t
                    else
                      var_type = AST::Builtin.any_type
                    end
                  end
                end
              end
            end
            var_name = asgn.children[0] #: Symbol

            if var_type
              if body
                body_constr = constr.update_type_env do |type_env|
                  type_env = type_env.assign_local_variables({ var_name => var_type })
                  pins = type_env.pin_local_variables(nil)
                  type_env.merge(local_variable_types: pins)
                end

                typing.cursor_context.set_body_context(node, body_constr.context)
                _, _, body_context = body_constr.synthesize(body).to_ary

                constr = constr.update_type_env do |env|
                  env.join(collection_context.type_env, body_context.type_env)
                end
              else
                constr = self
              end

              add_typing(node, type: collection_type, constr: constr)
            else
              constr = synthesize_children(node, skips: [collection])

              constr.fallback_to_any(node) do
                Diagnostic::Ruby::NoMethod.new(
                  node: node,
                  method: :each,
                  type: collection_type
                )
              end
            end
          end
        when :while, :until
          yield_self do
            cond, body = node.children
            cond_type, constr = synthesize(cond, condition: true).to_ary

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing, config: builder_config)
            truthy, falsy = interpreter.eval(env: constr.context.type_env, node: cond)
            truthy_env = truthy.env
            falsy_env = falsy.env

            case node.type
            when :while
              body_env, exit_env = truthy_env, falsy_env
            when :until
              exit_env, body_env = truthy_env, falsy_env
            else
              raise
            end

            body_env or raise
            exit_env or raise


            if body
              pins = body_env.pin_local_variables(nil)
              body_env = body_env.merge(local_variable_types: pins)

              _, body_constr =
                constr
                  .update_type_env { body_env }
                  .for_branch(body, break_context: TypeInference::Context::BreakContext.new(break_type: hint || AST::Builtin.nil_type, next_type: nil))
                  .tap {|constr| typing.cursor_context.set_node_context(body, constr.context) }
                  .synthesize(body).to_ary

              constr = constr.update_type_env {|env| env.join(exit_env, body_constr.context.type_env) }
            else
              constr = constr.update_type_env { exit_env }
            end

            add_typing(node, type: AST::Builtin.nil_type, constr: constr)
          end

        when :while_post, :until_post
          yield_self do
            cond, body = node.children

            _, cond_constr, = synthesize(cond)

            if body
              for_loop =
                cond_constr
                  .update_type_env {|env| env.merge(local_variable_types: env.pin_local_variables(nil)) }
                  .for_branch(body, break_context: TypeInference::Context::BreakContext.new(break_type: hint || AST::Builtin.nil_type, next_type: nil))

              typing.cursor_context.set_node_context(body, for_loop.context)
              _, body_constr, body_context = for_loop.synthesize(body)

              constr = cond_constr.update_type_env {|env| env.join(env, body_context.type_env) }

              add_typing(node, type: AST::Builtin.nil_type, constr: constr)
            else
              add_typing(node, type: AST::Builtin.nil_type, constr: cond_constr)
            end
          end

        when :irange, :erange
          begin_node, end_node = node.children

          constr = self
          begin_type, constr = if begin_node
                                 constr.synthesize(begin_node).to_ary
                               else
                                 [AST::Builtin.nil_type, constr]
                               end
          end_type, constr = if end_node
                               constr.synthesize(end_node).to_ary
                             else
                               [AST::Builtin.nil_type, constr]
                             end

          type = AST::Builtin::Range.instance_type(union_type(begin_type, end_type))
          add_typing(node, type: type, constr: constr)

        when :regexp
          each_child_node(node) do |child|
            synthesize(child)
          end

          add_typing(node, type: AST::Builtin::Regexp.instance_type)

        when :regopt
          # ignore
          add_typing(node, type: AST::Builtin.any_type)

        when :nth_ref
          add_typing(node, type: union_type(AST::Builtin::String.instance_type, AST::Builtin.nil_type))

        when :back_ref
          synthesize(node.updated(:gvar), hint: hint)

        when :or_asgn, :and_asgn
          yield_self do
            asgn, rhs = node.children

            case asgn.type
            when :lvasgn
              type, constr = synthesize(rhs, hint: hint)
              constr.lvasgn(asgn, type)
            when :ivasgn
              type, constr = synthesize(rhs, hint: hint)
              constr.ivasgn(asgn, type)
            when :gvasgn
              type, constr = synthesize(rhs, hint: hint)
              constr.gvasgn(asgn, type)
            when :send
              children = asgn.children.dup
              children[1] = :"#{children[1]}="
              send_arg_nodes = [*children, rhs]
              rhs_ = node.updated(:send, send_arg_nodes)
              node_type = case node.type
                          when :or_asgn
                            :or
                          when :and_asgn
                            :and
                          end
              node_ = node.updated(node_type, [asgn, rhs_])

              synthesize(node_, hint: hint)
            else
              Steep.logger.error { "#{node.type} with #{asgn.type} lhs is not supported"}
              fallback_to_any(node)
            end
          end

        when :defined?
          type_any_rec(node, only_children: true)
          add_typing(node, type: AST::Builtin.optional(AST::Builtin::String.instance_type))

        when :gvasgn
          yield_self do
            name, rhs = node.children
            lhs_type = context.type_env[name]
            rhs_type, constr = synthesize(rhs, hint: lhs_type).to_ary

            location = node.location #: Parser::Source::Map & Parser::AST::_Variable
            constr.check_deprecation_global(name, node, location.name)

            type, constr = constr.gvasgn(node, rhs_type)

            constr.add_typing(node, type: type)
          end

        when :gvar
          yield_self do
            name = node.children.first

            check_deprecation_global(name, node, node.location.expression)

            if type = context.type_env[name]
              add_typing(node, type: type)
            else
              fallback_to_any(node) do
                Diagnostic::Ruby::UnknownGlobalVariable.new(node: node, name: name)
              end
            end
          end

        when :block_pass
          yield_self do
            value_node = node.children[0]

            constr = self #: TypeConstruction

            if value_node
              type, constr = synthesize(value_node, hint: hint)

              if hint.is_a?(AST::Types::Proc) && value_node.type == :send && value_node.children[1] == :method && AST::Builtin::Method.instance_type?(type)
                receiver_node = value_node.children[0] #: Parser::AST::Node?
                receiver_type = receiver_node ? typing.type_of(node: receiver_node) : self_type
                method_name = value_node.children[2].children[0] #: Symbol
                if method = calculate_interface(receiver_type, private: true)&.methods&.[](method_name)
                  if method_type = method.method_types.find {|method_type| method_type.accept_one_arg? }
                    if method_type.type_params.empty?
                      type = AST::Types::Proc.new(
                        type: method_type.type,
                        block: method_type.block,
                        self_type: nil
                      )
                    end
                  end
                end
              elsif hint.is_a?(AST::Types::Proc) && value_node.type == :sym
                if hint.one_arg?
                  if hint.type.params
                    # Assumes Symbol#to_proc implementation
                    param_type = hint.type.params.required.fetch(0)
                    case param_type
                    when AST::Types::Any
                      type = AST::Types::Any.instance
                    else
                      if method = calculate_interface(param_type, private: true)&.methods&.[](value_node.children[0])
                        return_types = method.method_types.filter_map do |method_type|
                          if method_type.type.params.nil? || method_type.type.params.optional?
                            method_type.type.return_type
                          end
                        end

                        unless return_types.empty?
                          type = AST::Types::Proc.new(
                            type: Interface::Function.new(
                              params: Interface::Function::Params.empty.with_first_param(
                                Interface::Function::Params::PositionalParams::Required.new(param_type)
                              ),
                              return_type: return_types.fetch(0),
                              location: nil
                            ),
                            block: nil,
                            self_type: nil
                          )
                        end
                      end
                    end
                  end
                else
                  Steep.logger.error "Passing multiple args through Symbol#to_proc is not supported yet"
                end
              end

              case
              when type.is_a?(AST::Types::Proc)
                # nop
              when AST::Builtin::Proc.instance_type?(type)
                # nop
              else
                type = try_convert(type, :to_proc) || type
              end
            else
              # Anonymous block_pass only happens inside method definition
              if block_type = method_context!.block_type
                type = AST::Types::Proc.new(
                  type: block_type.type,
                  block: nil,
                  self_type: block_type.self_type
                )

                if block_type.optional?
                  type = union_type(type, AST::Builtin.nil_type)
                end
              else
                type = AST::Builtin.nil_type
              end
            end

            add_typing node, type: type
          end

        when :blockarg
          yield_self do
            each_child_node node do |child|
              synthesize(child)
            end

            add_typing node, type: AST::Builtin.any_type
          end

        when :cvasgn
          name, rhs = node.children

          type, constr = synthesize(rhs, hint: hint)

          var_type =
            if class_vars = module_context.class_variables
              if ty = class_vars[name]
                checker.factory.type(ty)
              end
            end

          if var_type
            result = constr.check_relation(sub_type: type, super_type: var_type)

            if result.success?
              add_typing node, type: type, constr: constr
            else
              fallback_to_any node do
                Diagnostic::Ruby::IncompatibleAssignment.new(
                  node: node,
                  lhs_type: var_type,
                  rhs_type: type,
                  result: result
                )
              end
            end
          else
            fallback_to_any(node)
          end

        when :cvar
          name = node.children[0] #: Symbol
          var_type =
            if cvs = module_context.class_variables
              if ty = cvs[name]
                checker.factory.type(ty)
              end
            end

          if var_type
            add_typing node, type: var_type
          else
            fallback_to_any node
          end

        when :alias
          add_typing node, type: AST::Builtin.nil_type

        when :splat
          yield_self do
            typing.add_error(
              Diagnostic::Ruby::UnsupportedSyntax.new(
                node: node,
                message: "Unsupported splat node occurrence"
              )
            )

            each_child_node node do |child|
              synthesize(child)
            end

            add_typing node, type: AST::Builtin.any_type
          end

        when :args
          constr = self #: TypeConstruction

          each_child_node(node) do |child|
            _, constr = constr.synthesize(child)
          end

          add_typing node, type: AST::Builtin.any_type, constr: constr

        when :assertion
          yield_self do
            # @type var as_type: AST::Node::TypeAssertion
            asserted_node, as_type = node.children

            type = as_type.type(module_context.nesting, checker, [])

            case type
            when Array
              type.each do |error|
                typing.add_error(
                  Diagnostic::Ruby::RBSError.new(
                    error: error,
                    node: node,
                    location: error.location || raise
                  )
                )
              end

              synthesize(asserted_node, hint: hint)

            when nil, RBS::ParsingError
              synthesize(asserted_node, hint: hint)

            else
              actual_type, constr = synthesize(asserted_node, hint: type)

              if no_subtyping?(sub_type: type, super_type: actual_type) && no_subtyping?(sub_type: actual_type, super_type: type)
                typing.add_error(
                  Diagnostic::Ruby::FalseAssertion.new(
                    node: node,
                    assertion_type: type,
                    node_type: actual_type
                  )
                )
              end

              constr.add_typing(node, type: type)
            end
          end

        when :tapp
          yield_self do
            # @type var tapp: AST::Node::TypeApplication
            sendish, tapp = node.children

            if (array = tapp.types(module_context.nesting, checker, [])).is_a?(Enumerator)
              array.each do |error|
                typing.add_error(
                  Diagnostic::Ruby::RBSError.new(
                    error: error,
                    node: node,
                    location: error.location || raise
                  )
                )
              end
            end

            type, constr = synthesize_sendish(sendish, hint: hint, tapp: tapp)

            constr.add_typing(node, type: type)
          end

        when :block, :numblock, :send, :csend
          synthesize_sendish(node, hint: hint, tapp: nil)

        when :forwarded_args, :forward_arg
          add_typing(node, type: AST::Builtin.any_type)

        else
          typing.add_error(Diagnostic::Ruby::UnsupportedSyntax.new(node: node))
          add_typing(node, type: AST::Builtin.any_type)

        end.tap do |pair|
          unless pair.is_a?(Pair) && !pair.type.is_a?(Pair)
            # Steep.logger.error { "result = #{pair.inspect}" }
            # Steep.logger.error { "node = #{node.type}" }
            raise "#synthesize should return an instance of Pair: #{pair.class}, node=#{node.inspect}"
          end
        end
      rescue RBS::BaseError => exn
        Steep.logger.warn { "Unexpected RBS error: #{exn.message}" }
        exn.backtrace&.each {|loc| Steep.logger.warn "  #{loc}" }
        typing.add_error(Diagnostic::Ruby::UnexpectedError.new(node: node, error: exn))
        type_any_rec(node)
      rescue StandardError => exn
        Steep.log_error exn
        typing.add_error(Diagnostic::Ruby::UnexpectedError.new(node: node, error: exn))
        type_any_rec(node)
      end
    end

    def check(node, type, constraints: Subtyping::Constraints.empty)
      pair = synthesize(node, hint: type)

      result = check_relation(sub_type: pair.type, super_type: type, constraints: constraints)
      if result.failure?
        yield(type, pair.type, result)
        pair.with(type: type)
      else
        pair
      end
    end

    def synthesize_sendish(node, hint:, tapp:)
      case node.type
      when :send
        type_send(node, send_node: node, block_params: nil, block_body: nil, tapp: tapp, hint: hint)
      when :csend
        yield_self do
          send_type, constr =
            type_send(node, send_node: node, block_params: nil, block_body: nil, unwrap: true, tapp: tapp, hint: hint).to_ary

          constr
            .update_type_env { context.type_env.join(constr.context.type_env, context.type_env) }
            .add_typing(node, type: union_type(send_type, AST::Builtin.nil_type))
        end
      when :block
        yield_self do
          send_node, params, body = node.children
          if send_node.type == :lambda
            # @type var node: Parser::AST::Node & Parser::AST::_BlockNode
            type_lambda(node, params_node: params, body_node: body, type_hint: hint)
          else
            type_send(node, send_node: send_node, block_params: params, block_body: body, unwrap: send_node.type == :csend, tapp: tapp, hint: hint)
          end
        end
      when :numblock
        yield_self do
          send_node, max_num, body = node.children

          if max_num == 1
            arg_nodes = [Parser::AST::Node.new(:procarg0, [:_1])]
          else
            arg_nodes = max_num.times.map {|i| Parser::AST::Node.new(:arg, [:"_#{i+1}"]) }
          end

          params = Parser::AST::Node.new(:args, arg_nodes)

          if send_node.type == :lambda
            # @type var node: Parser::AST::Node & Parser::AST::_BlockNode
            type_lambda(node, params_node: params, body_node: body, type_hint: hint)
          else
            type_send(node, send_node: send_node, block_params: params, block_body: body, unwrap: send_node.type == :csend, tapp: tapp, hint: hint)
          end
        end
      else
        raise "Unexpected node is given to `#synthesize_sendish` (#{node.type}, #{node.location.first_line})"
      end
    end

    def masgn_lhs?(lhs)
      lhs.children.all? do |a|
        asgn_type = if a.type == :splat
                      a.children[0]&.type
                    else
                      a.type
                    end
        asgn_type.nil? || asgn_type == :lvasgn || asgn_type == :ivasgn || asgn_type == :gvasgn
      end
    end

    def lvasgn(node, type)
      name = node.children[0]

      if SPECIAL_LVAR_NAMES.include?(name)
        add_typing(node, type: AST::Builtin.any_type)
      else
        if enforced_type = context.type_env.enforced_type(name)
          if result = no_subtyping?(sub_type: type, super_type: enforced_type)
            typing.add_error(
              Diagnostic::Ruby::IncompatibleAssignment.new(
                node: node,
                lhs_type: enforced_type,
                rhs_type: type,
                result: result
              )
            )

            type = enforced_type
          end
        end

        update_type_env {|env| env.assign_local_variable(name, type, enforced_type) }
          .add_typing(node, type: type)
      end
    end

    def ivasgn(node, rhs_type)
      name = node.children[0]

      lhs_type = context.type_env[name]

      if lhs_type
        if (result = check_relation(sub_type: rhs_type, super_type: lhs_type)).failure?
          typing.add_error(
            Diagnostic::Ruby::IncompatibleAssignment.new(node: node, lhs_type: lhs_type, rhs_type: rhs_type, result: result)
          )
        end
      else
        typing.add_error(Diagnostic::Ruby::UnknownInstanceVariable.new(node: node, name: name))
      end

      add_typing(node, type: rhs_type)
    end

    def gvasgn(node, rhs_type)
      name = node.children[0]

      lhs_type = context.type_env[name]

      if lhs_type
        if result = no_subtyping?(sub_type: rhs_type, super_type: lhs_type)
          typing.add_error(
            Diagnostic::Ruby::IncompatibleAssignment.new(node: node, lhs_type: lhs_type, rhs_type: rhs_type, result: result)
          )
        end
      else
        typing.add_error(Diagnostic::Ruby::UnknownGlobalVariable.new(node: node, name: name))
      end

      add_typing(node, type: rhs_type)
    end

    def type_masgn_type(mlhs_node, rhs_type, masgn:, optional:)
      # @type var constr: TypeConstruction
      constr = self

      if assignments = masgn.expand(mlhs_node, rhs_type || AST::Builtin.any_type, optional)
        assignments.each do |pair|
          node, type = pair

          if assignments.optional
            type = AST::Builtin.optional(type)
          end

          if node.type == :splat
            asgn_node = node.children[0]
            next unless asgn_node
            var_type = asgn_node.type
          else
            asgn_node = node
            var_type = type
          end

          case asgn_node.type
          when :lvasgn
            _, constr = constr.lvasgn(asgn_node, type)
          when :ivasgn
            _, constr = constr.ivasgn(asgn_node, type)
          when :gvasgn
            _, constr = constr.gvasgn(asgn_node, type)
          when :mlhs
            constr = (constr.type_masgn_type(asgn_node, type, masgn: masgn, optional: optional) or return)
          else
            _, constr = constr.synthesize_children(asgn_node).add_typing(asgn_node, type: AST::Builtin.any_type)
          end

          if node.type == :splat
            _, constr = constr.add_typing(node, type: type)
          end
        end

        constr
      end
    end

    def type_masgn(node)
      lhs, rhs = node.children

      masgn = TypeInference::MultipleAssignment.new()
      hint = masgn.hint_for_mlhs(lhs, context.type_env)

      rhs_type, lhs_constr = try_tuple_type!(rhs, hint: hint).to_ary
      rhs_type = deep_expand_alias(rhs_type) || rhs_type

      falsys, truthys = partition_flatten_types(rhs_type) do |type|
        type.is_a?(AST::Types::Nil) || (type.is_a?(AST::Types::Literal) && type.value == false)
      end

      truthy_rhs_type = union_type_unify(*truthys)
      if truthy_rhs_type.is_a?(AST::Types::Union)
        tup = union_of_tuple_to_tuple_of_union(truthy_rhs_type)
        truthy_rhs_type = tup if tup
      end
      optional = !falsys.empty?

      if truthy_rhs_type.is_a?(AST::Types::Tuple) || AST::Builtin::Array.instance_type?(truthy_rhs_type) || truthy_rhs_type.is_a?(AST::Types::Any)
        constr = lhs_constr.type_masgn_type(lhs, truthy_rhs_type, masgn: masgn, optional: optional)
      else
        ary_type = try_convert(truthy_rhs_type, :to_ary) || try_convert(truthy_rhs_type, :to_a) || AST::Types::Tuple.new(types: [truthy_rhs_type])
        constr = lhs_constr.type_masgn_type(lhs, ary_type, masgn: masgn, optional: optional)
      end

      unless constr
        typing.add_error(
          Diagnostic::Ruby::MultipleAssignmentConversionError.new(
            node: rhs,
            original_type: rhs_type,
            returned_type: ary_type || AST::Builtin.bottom_type
          )
        )

        constr = lhs_constr

        each_descendant_node(lhs) do |node|
          case node.type
          when :lvasgn
            _, constr = constr.lvasgn(node, AST::Builtin.any_type)
          when :ivasgn
            _, constr = constr.ivasgn(node, AST::Builtin.any_type)
          when :gvasgn
            _, constr = constr.gvasgn(node, AST::Builtin.any_type)
          else
            _, constr = constr.add_typing(node, type: AST::Builtin.any_type).to_ary
          end
        end
      end

      constr.add_typing(node, type: truthy_rhs_type)
    end

    def synthesize_constant_decl(node, parent_node, constant_name, &block)
      const_name = module_name_from_node(parent_node, constant_name)

      if const_name && type = context.type_env.annotated_constant(const_name)
        # const-type annotation wins
        if node
          constr = synthesize_children(node)
          type, constr = constr.add_typing(node, type: type)
          [type, constr, nil]
        else
          [type, self, nil]
        end
      else
        if parent_node
          synthesize_constant(node, parent_node, constant_name, &block)
        else
          if nesting
            if parent_nesting = nesting[1]
              if constant = context.type_env.constant_env.resolver.table.children(parent_nesting)&.fetch(constant_name, nil)
                return [checker.factory.type(constant.type), self, constant.name]
              end
            end

            if block_given?
              yield
            else
              if node
                typing.add_error(
                  Diagnostic::Ruby::UnknownConstant.new(node: node, name: constant_name)
                )
              end
            end

            constr = self #: TypeConstruction
            if node
              _, constr = add_typing(node, type: AST::Builtin.any_type)
            end

            [
              AST::Builtin.any_type,
              constr,
              nil
            ]
          else
            # No nesting
            synthesize_constant(node, nil, constant_name, &block)
          end
        end
      end
    end

    def synthesize_constant(node, parent_node, constant_name)
      const_name = module_name_from_node(parent_node, constant_name)

      if const_name && type = context.type_env.annotated_constant(const_name)
        # const-type annotation wins
        if node
          constr = synthesize_children(node)
          type, constr = constr.add_typing(node, type: type)
          [type, constr, nil]
        else
          [type, self, nil]
        end
      else
        case
        when !parent_node
          constr = self

          if (type, name = context.type_env.constant(constant_name, false))
            if node
              _, constr = add_typing(node, type: type)
            end

            return [type, constr, name]
          end
        when parent_node.type == :cbase
          _, constr = add_typing(parent_node, type: AST::Builtin.nil_type)

          if (type, name = constr.context.type_env.constant(constant_name, true))
            if node
              _, constr = constr.add_typing(node, type: type)
            end

            return [type, constr, name]
          end
        else
          parent_type, constr = synthesize(parent_node).to_ary
          parent_type = expand_self(parent_type)
          parent_type = deep_expand_alias(parent_type)

          case parent_type
          when AST::Types::Name::Singleton
            if (type, name = constr.context.type_env.constant(parent_type.name, constant_name))
              if node
                _, constr = add_typing(node, type: type)
              end

              return [type, constr, name]
            end
          when AST::Types::Any
            # Couldn't detect the type of the parent constant
            # Skip reporting error for this node.
            if node
              _, constr = add_typing(node, type: parent_type)
            end

            return [parent_type, constr, nil]
          end
        end

        if block_given?
          yield
        else
          if node
            constr.typing.add_error(
              Diagnostic::Ruby::UnknownConstant.new(node: node, name: constant_name)
            )
          end
        end

        if node
          _, constr = add_typing(node, type: AST::Builtin.any_type)
        end

        [AST::Builtin.any_type, constr, nil]
      end
    end

    def optional_proc?(type)
      if type.is_a?(AST::Types::Union)
        if type.types.size == 2
          if type.types.find {|t| t.is_a?(AST::Types::Nil) }
            if proc_type = type.types.find {|t| t.is_a?(AST::Types::Proc) }
              proc_type #: AST::Types::Proc
            end
          end
        end
      end
    end

    def type_lambda(node, params_node:, body_node:, type_hint:)
      block_annotations = source.annotations(block: node, factory: checker.factory, context: nesting)
      params = TypeInference::BlockParams.from_node(params_node, annotations: block_annotations)

      if type_hint
        original_hint = type_hint

        type_hint = deep_expand_alias(type_hint) || type_hint

        unless type_hint.is_a?(AST::Types::Any)
          procs = flatten_union(type_hint).select do |type|
            check_relation(sub_type: type, super_type: AST::Builtin::Proc.instance_type).success? &&
              !type.is_a?(AST::Types::Any)
          end

          proc_instances, proc_types = procs.partition {|type| AST::Builtin::Proc.instance_type?(type) }

          case
          when !proc_instances.empty? && proc_types.empty?
            # `::Proc` is given as a hint
          when proc_types.size == 1
            # Proc type is given as a hint
            hint_proc = proc_types[0]  #: AST::Types::Proc
            params_hint = hint_proc.type.params
            return_hint = hint_proc.type.return_type
            block_hint = hint_proc.block
            self_hint = hint_proc.self_type
          else
            typing.add_error(
              Diagnostic::Ruby::ProcHintIgnored.new(hint_type: original_hint, node: node)
            )
          end
        end
      end

      block_constr = for_block(
        body_node,
        block_params: params,
        block_param_hint: params_hint,
        block_next_type: return_hint,
        block_block_hint: block_hint,
        block_annotations: block_annotations,
        block_self_hint: self_hint,
        node_type_hint: nil
      )

      block_constr.typing.cursor_context.set_body_context(node, block_constr.context)

      params.each_single_param do |param|
        _, block_constr = block_constr.synthesize(param.node, hint: param.type)
      end

      block =
        if block_param = params.block_param
          if block_param_type = block_param.type
            case block_param_type
            when AST::Types::Proc
              Interface::Block.new(type: block_param_type.type, optional: false, self_type: block_param_type.self_type)
            else
              if proc_type = optional_proc?(block_param_type)
                Interface::Block.new(type: proc_type.type, optional: true, self_type: proc_type.self_type)
              else
                block_constr.typing.add_error(
                  Diagnostic::Ruby::ProcTypeExpected.new(
                    node: block_param.node,
                    type: block_param_type
                  )
                )

                Interface::Block.new(
                  type: Interface::Function.new(
                    params: Interface::Function::Params.empty,
                    return_type: AST::Builtin.any_type,
                    location: nil
                  ),
                  optional: false,
                  self_type: nil
                )
              end
            end
          else
            block_hint
          end
        end

      if body_node
        return_type = block_constr.synthesize_block(
          node: node,
          block_body: body_node,
          block_type_hint: return_hint
        )

        return_type = return_type.subst(
          Interface::Substitution.build([], [], self_type: block_constr.self_type)
        )

        if expected_block_type = block_constr.block_context!.body_type
          type_vars = expected_block_type.free_variables.filter_map do |var|
            case var
            when Symbol
              var
            end
          end
          subst = Interface::Substitution.build(type_vars, type_vars.map { AST::Builtin.any_type })
          expected_block_type = expected_block_type.subst(subst)

          check_relation(sub_type: return_type, super_type: expected_block_type).else do |result|
            block_constr.typing.add_error(
              Diagnostic::Ruby::BlockBodyTypeMismatch.new(
                node: node,
                expected: expected_block_type,
                actual: return_type,
                result: result
              )
            )

            return_type = expected_block_type
          end
        end
      else
        return_type = AST::Builtin.any_type
      end

      block_type = AST::Types::Proc.new(
        type: Interface::Function.new(
          params: params_hint || params.params_type,
          return_type: return_type,
          location: nil
        ),
        block: block,
        self_type: block_annotations.self_type || self_hint
      )

      add_typing node, type: block_type
    end

    def synthesize_children(node, skips: [])
      skips = Set.new.compare_by_identity.merge(skips).delete(nil)

      # @type var constr: TypeConstruction
      constr = self

      each_child_node(node) do |child|
        unless skips.include?(child)
          _, constr = constr.synthesize(child)
        end
      end

      constr
    end

    KNOWN_PURE_METHODS = Set[
      MethodName("::Array#[]"),
      MethodName("::Hash#[]")
    ]

    def pure_send?(call, receiver, arguments)
      return false unless call.node.type == :send || call.node.type == :csend
      return false unless call.pure? || KNOWN_PURE_METHODS.superset?(Set.new(call.method_decls.map(&:method_name)))

      argishes = [*arguments]
      argishes << receiver if receiver

      argishes.all? do |node|
        value_node?(node) || context.type_env[node]
      end
    end

    def deprecated_send?(call)
      return unless call.node.type == :send || call.node.type == :csend

      call.method_decls.each do |decl|
        if pair = AnnotationsHelper.deprecated_annotation?(decl.method_def.each_annotation.to_a)
          return pair
        end
      end

      nil
    end

    def type_send_interface(node, interface:, receiver:, receiver_type:, method_name:, arguments:, block_params:, block_body:, tapp:, hint:)
      method = interface.methods[method_name]

      if method
        call, constr = type_method_call(
          node,
          method: method,
          method_name: method_name,
          arguments: arguments,
          block_params: block_params,
          block_body: block_body,
          receiver_type: receiver_type,
          tapp: tapp,
          hint: hint
        )

        if call && constr
          case method_name.to_s
          when "[]="
            if test_send_node(node) {|_, _, _, loc| !loc.dot }
              last_arg = arguments.last or raise
              if typing.has_type?(last_arg)
                call = call.with_return_type(typing.type_of(node: last_arg))
              end
            end
          when /\w=\Z/
            last_arg = arguments.last or raise
            if typing.has_type?(last_arg)
              call = call.with_return_type(typing.type_of(node: last_arg))
            end
          end

          if call.is_a?(TypeInference::MethodCall::Typed)
            if (pure_call, type = constr.context.type_env.pure_method_calls.fetch(node, nil))
              if type
                call = pure_call.update(node: node, return_type: type)
                constr.add_typing(node, type: call.return_type)
              end
            else
              if pure_send?(call, receiver, arguments)
                constr = constr.update_type_env do |env|
                  env.add_pure_call(node, call, call.return_type)
                end
              else
                constr = constr.update_type_env do |env|
                  if receiver
                    env.invalidate_pure_node(receiver)
                  else
                    env
                  end
                end
              end
            end

            if (_, message = deprecated_send?(call))
              send_node, _ = deconstruct_sendish_and_block_nodes(node)
              send_node or raise
              _, _, _, loc = deconstruct_send_node!(send_node)

              constr.typing.add_error(
                Diagnostic::Ruby::DeprecatedReference.new(
                  node: node,
                  location: loc.selector,
                  message: message
                )
              )
            end
          end

          if node.type == :csend || ((node.type == :block || node.type == :numblock) && node.children[0].type == :csend)
            optional_type = AST::Types::Union.build(types: [call.return_type, AST::Builtin.nil_type])
            call = call.with_return_type(optional_type)
          end
        else
          errors = [] #: Array[Diagnostic::Ruby::Base]

          skips = [receiver]
          skips << node.children[0] if node.type == :block

          constr = synthesize_children(node, skips: skips)
          if block_params
            # @type var node: Parser::AST::Node & Parser::AST::_BlockNode
            block_annotations = source.annotations(block: node, factory: checker.factory, context: nesting)

            constr.type_block_without_hint(
              node: node,
              block_params: TypeInference::BlockParams.from_node(block_params, annotations: block_annotations),
              block_annotations: block_annotations,
              block_body: block_body
            ) do |error|
              errors << error
            end
          end

          errors << Diagnostic::Ruby::UnresolvedOverloading.new(
            node: node,
            receiver_type: interface.type,
            method_name: method_name,
            method_types: method.method_types
          )

          decls =  method.overloads.flat_map do |method_overload|
            method_overload.method_decls(method_name)
          end.to_set

          call = TypeInference::MethodCall::Error.new(
            node: node,
            context: context.call_context,
            method_name: method_name,
            receiver_type: receiver_type,
            errors: errors,
            method_decls: decls
          )
        end

        constr.add_call(call)
      else
        skips = [] #: Array[Parser::AST::Node?]
        skips << receiver if receiver
        skips << node.children[0] if node.type == :block
        skips << block_params if block_params
        skips << block_body if block_body

        constr = synthesize_children(node, skips: skips)
        if block_params
          # @type var node: Parser::AST::Node & Parser::AST::_BlockNode
          block_annotations = source.annotations(block: node, factory: checker.factory, context: nesting)

          constr.type_block_without_hint(
            node: node,
            block_params: TypeInference::BlockParams.from_node(block_params, annotations: block_annotations),
            block_annotations: block_annotations,
            block_body: block_body
          )
        end

        if node.type == :block
          send_node = node.children[0]
          case send_node.type
          when :super, :zsuper
            method_name = method_context!.name or raise
            return fallback_to_any(send_node) do
              Diagnostic::Ruby::UnexpectedSuper.new(node: send_node, method: method_name)
            end
          end
        end

        constr.add_call(
          TypeInference::MethodCall::NoMethodError.new(
            node: node,
            context: context.call_context,
            method_name: method_name,
            receiver_type: receiver_type,
            error: Diagnostic::Ruby::NoMethod.new(node: node, method: method_name, type: interface&.type || receiver_type)
          )
        )
      end
    end

    def type_send(node, send_node:, block_params:, block_body:, unwrap: false, tapp:, hint:)
      # @type var constr: TypeConstruction
      # @type var receiver: Parser::AST::Node?

      case send_node.type
      when :super, :zsuper
        receiver = nil
        method_name = method_context!.name
        arguments = send_node.children

        if method_name.nil? || method_context!.super_method.nil?
          return fallback_to_any(send_node) do
            Diagnostic::Ruby::UnexpectedSuper.new(
              node: send_node,
              method: method_context&.name
            )
          end
        end

        recv_type = AST::Types::Self.instance
        constr = self
      else
        receiver, method_name, *arguments = send_node.children

        case method_name
        when :attr_reader
          arguments.each do |argnode|
            module_context.defined_instance_methods << argnode.children[0]
          end
        when :attr_writer
          arguments.each do |argnode|
            module_context.defined_instance_methods << :"#{argnode.children[0]}="
          end
        when :attr_accessor
          arguments.each do |argnode|
            module_context.defined_instance_methods << argnode.children[0]
            module_context.defined_instance_methods << :"#{argnode.children[0]}="
          end
        end

        if receiver
          recv_type, constr = synthesize(receiver)
        else
          recv_type = AST::Types::Self.instance
          constr = self
        end
      end

      if unwrap
        recv_type = unwrap(recv_type)
      end

      receiver_type = checker.factory.deep_expand_alias(recv_type)
      private = receiver.nil? || receiver.type == :self

      type, constr =
        case receiver_type
        when nil
          raise

        when AST::Types::Any
          case node.type
          when :block, :numblock
            # @type var node: Parser::AST::Node & Parser::AST::_BlockNode
            block_annotations = source.annotations(block: node, factory: checker.factory, context: nesting)
            block_params or raise

            constr = constr.synthesize_children(node.children[0], skips: [receiver])

            constr.type_block_without_hint(
              node: node,
              block_params: TypeInference::BlockParams.from_node(block_params, annotations: block_annotations),
              block_annotations: block_annotations,
              block_body: block_body
            ) do |error|
              constr.typing.errors << error
            end
          else
            constr = constr.synthesize_children(node, skips: [receiver])
          end

          constr.add_call(
            TypeInference::MethodCall::Untyped.new(
              node: node,
              context: context.call_context,
              method_name: method_name
            )
          )
        else
          if interface = calculate_interface(receiver_type, private: private)
            constr.type_send_interface(
              node,
              interface: interface,
              receiver: receiver,
              receiver_type: receiver_type,
              method_name: method_name,
              arguments: arguments,
              block_params: block_params,
              block_body: block_body,
              tapp: tapp,
              hint: hint
            )
          else
            constr = constr.synthesize_children(node, skips: [receiver])
            constr.add_call(
              TypeInference::MethodCall::NoMethodError.new(
                node: node,
                context: context.call_context,
                method_name: method_name,
                receiver_type: receiver_type,
                error: Diagnostic::Ruby::NoMethod.new(node: node, method: method_name, type: receiver_type)
              )
            )
          end
        end

      Pair.new(type: type, constr: constr)
    end

    def builder_config
      Interface::Builder::Config.new(
        self_type: self_type,
        class_type: module_context.module_type,
        instance_type: module_context.instance_type,
        variable_bounds: context.variable_context.upper_bounds
      )
    end

    def calculate_interface(type, method_name = nil, private:)
      shape = checker.builder.shape(type, builder_config)

      unless private
        shape = shape&.public_shape
      end

      if method_name
        if shape
          shape.methods[method_name]
        end
      else
        shape
      end
    end

    def expand_self(type)
      if type.is_a?(AST::Types::Self) && self_type
        self_type
      else
        type
      end
    end

    SPECIAL_METHOD_NAMES = {
      array_compact: Set[
        MethodName("::Array#compact"),
        MethodName("::Enumerable#compact")
      ],
      hash_compact: Set[
        MethodName("::Hash#compact")
      ],
      lambda: Set[
        MethodName("::Kernel#lambda"),
        MethodName("::Kernel.lambda")
      ]
    }

    def try_special_method(node, receiver_type:, method_name:, method_overload:, arguments:, block_params:, block_body:, hint:)
      method_type = method_overload.method_type
      decls = method_overload.method_decls(method_name).to_set

      case
      when decl = decls.find {|decl| SPECIAL_METHOD_NAMES.fetch(:array_compact).include?(decl.method_name) }
        if arguments.empty? && !block_params
          # compact
          return_type = method_type.type.return_type
          if AST::Builtin::Array.instance_type?(return_type)
            # @type var return_type: AST::Types::Name::Instance
            elem = return_type.args.fetch(0)
            type = AST::Builtin::Array.instance_type(unwrap(elem))

            _, constr = add_typing(node, type: type)
            call = TypeInference::MethodCall::Special.new(
              node: node,
              context: constr.context.call_context,
              method_name: decl.method_name.method_name,
              receiver_type: receiver_type,
              actual_method_type: method_type.with(type: method_type.type.with(return_type: type)),
              return_type: type,
              method_decls: decls
            )

            return [call, constr]
          end
        end
      when decl = decls.find {|decl| SPECIAL_METHOD_NAMES.fetch(:hash_compact).include?(decl.method_name) }
        if arguments.empty? && !block_params
          # compact
          return_type = method_type.type.return_type
          if AST::Builtin::Hash.instance_type?(return_type)
            # @type var return_type: AST::Types::Name::Instance
            key = return_type.args.fetch(0)
            value = return_type.args.fetch(1)
            type = AST::Builtin::Hash.instance_type(key, unwrap(value))

            _, constr = add_typing(node, type: type)
            call = TypeInference::MethodCall::Special.new(
              node: node,
              context: constr.context.call_context,
              method_name: decl.method_name.method_name,
              receiver_type: receiver_type,
              actual_method_type: method_type.with(type: method_type.type.with(return_type: type)),
              return_type: type,
              method_decls: decls
            )

            return [call, constr]
          end
        end
      when decl = decls.find {|decl| SPECIAL_METHOD_NAMES.fetch(:lambda).include?(decl.method_name) }
        if block_params
          # @type var node: Parser::AST::Node & Parser::AST::_BlockNode
          type, constr = type_lambda(node, params_node: block_params, body_node: block_body, type_hint: hint)

          call = TypeInference::MethodCall::Special.new(
            node: node,
            context: context.call_context,
            method_name: decl.method_name.method_name,
            receiver_type: receiver_type,
            actual_method_type: method_type.with(type: method_type.type.with(return_type: type)),
            return_type: type,
            method_decls: decls
          )

          return [call, constr]
        end
      end

      nil
    end

    def type_method_call(node, method_name:, receiver_type:, method:, arguments:, block_params:, block_body:, tapp:, hint:)
      # @type var fails: Array[[TypeInference::MethodCall::t, TypeConstruction]]
      fails = []

      method.overloads.each do |overload|
        Steep.logger.tagged overload.method_type.to_s do
          typing.new_child() do |child_typing|
            constr = self.with_new_typing(child_typing)

            call, constr = constr.try_special_method(
              node,
              receiver_type: receiver_type,
              method_name: method_name,
              method_overload: overload,
              arguments: arguments,
              block_params: block_params,
              block_body: block_body,
              hint: hint
            ) || constr.try_method_type(
              node,
              receiver_type: receiver_type,
              method_name: method_name,
              method_overload: overload,
              arguments: arguments,
              block_params: block_params,
              block_body: block_body,
              tapp: tapp,
              hint: hint
            )

            if call.is_a?(TypeInference::MethodCall::Typed)
              constr.typing.save!
              return [
                call,
                update_type_env { constr.context.type_env }
              ]
            else
              fails << [call, constr]
            end
          end
        end
      end

      non_arity_errors = fails.reject do |call, _|
        if call.is_a?(TypeInference::MethodCall::Error)
          call.errors.any? do |error|
            error.is_a?(Diagnostic::Ruby::UnexpectedBlockGiven) ||
              error.is_a?(Diagnostic::Ruby::RequiredBlockMissing) ||
              error.is_a?(Diagnostic::Ruby::UnexpectedPositionalArgument) ||
              error.is_a?(Diagnostic::Ruby::InsufficientPositionalArguments) ||
              error.is_a?(Diagnostic::Ruby::UnexpectedKeywordArgument) ||
              error.is_a?(Diagnostic::Ruby::InsufficientKeywordArguments)
          end
        end
      end

      unless non_arity_errors.empty?
        fails = non_arity_errors
      end

      if fails.one?
        call, constr = fails.fetch(0)

        constr.typing.save!

        [
          call,
          update_type_env { constr.context.type_env }
        ]
      else
        nil
      end
    end

    def with_child_typing()
      constr = with_new_typing(typing.new_child())

      if block_given?
        yield constr
      else
        constr
      end
    end

    # Bypass :splat and :kwsplat
    def bypass_splat(node)
      splat = node.type == :splat || node.type == :kwsplat

      if splat
        pair = yield(node.children[0])
        pair.constr.add_typing(node, type: pair.type)
        pair
      else
        yield node
      end
    end

    def apply_solution(errors, node:, method_type:)
      subst = yield

      [
        method_type.subst(subst),
        true,
        subst
      ]

    rescue Subtyping::Constraints::UnsatisfiableConstraint => exn
      errors << Diagnostic::Ruby::UnsatisfiableConstraint.new(
        node: node,
        method_type: method_type,
        var: exn.var,
        sub_type: exn.sub_type,
        super_type: exn.super_type,
        result: exn.result
      )
      [method_type, false, Interface::Substitution.empty]
    end

    def eliminate_vars(type, variables, to: AST::Builtin.any_type)
      if variables.empty?
        type
      else
        subst = Interface::Substitution.build(variables, Array.new(variables.size, to))
        type.subst(subst)
      end
    end

    def type_check_untyped_args(arguments)
      constr = self #: TypeConstruction

      arguments.each do |arg|
        case arg.type
        when :splat
          type, constr = constr.synthesize(arg.children[0])
          _, constr = constr.add_typing(arg, type: type)
        when :kwargs
          _, constr = constr.type_hash_record(arg, nil) || constr.type_hash(arg, hint: nil)
        else
          _, constr = constr.synthesize(arg)
        end
      end

      constr
    end

    def type_check_args(method_name, args, constraints, errors)
      # @type var constr: TypeConstruction
      constr = self

      forwarded_args, es = args.each do |arg|
        case arg
        when TypeInference::SendArgs::PositionalArgs::NodeParamPair
          _, constr = constr.type_check_argument(
            arg.node,
            type: arg.param.type,
            constraints: constraints,
            errors: errors
          )

        when TypeInference::SendArgs::PositionalArgs::NodeTypePair
          _, constr = bypass_splat(arg.node) do |n|
            constr.type_check_argument(
              n,
              type: arg.node_type,
              constraints: constraints,
              report_node: arg.node,
              errors: errors
            )
          end

        when TypeInference::SendArgs::PositionalArgs::UnexpectedArg
          _, constr = bypass_splat(arg.node) do |n|
            constr.synthesize(n)
          end

        when TypeInference::SendArgs::PositionalArgs::SplatArg
          arg_type, _ =
            constr
              .with_child_typing()
              .try_tuple_type!(arg.node.children[0])
          arg.type = arg_type

        when TypeInference::SendArgs::PositionalArgs::MissingArg
          # ignore

        when TypeInference::SendArgs::KeywordArgs::ArgTypePairs
          arg.pairs.each do |pair|
            node, type = pair
            _, constr = bypass_splat(node) do |node|
              constr.type_check_argument(
                node,
                type: type,
                constraints: constraints,
                errors: errors
              )
            end
          end

        when TypeInference::SendArgs::KeywordArgs::UnexpectedKeyword
          if arg.node.type == :pair
            arg.node.children.each do |nn|
              _, constr = constr.synthesize(nn)
            end
          else
            _, constr = bypass_splat(arg.node) do |n|
              constr.synthesize(n)
            end
          end

        when TypeInference::SendArgs::KeywordArgs::SplatArg
          type, _ = bypass_splat(arg.node) do |sp_node|
            if sp_node.type == :hash
              pair = constr.type_hash_record(sp_node, nil) and break pair
            end

            constr.synthesize(sp_node)
          end

          arg.type = type

        when TypeInference::SendArgs::KeywordArgs::MissingKeyword
          # ignore

        else
          raise (_ = arg).inspect
        end
      end

      errors.push(*es)

      if forwarded_args
        method_name or raise "method_name cannot be nil if `forwarded_args` is given, because proc/block doesn't support `...` arg"

        method_context = context.method_context or raise
        forward_arg_type = method_context.forward_arg_type

        case forward_arg_type
        when nil
          if context.method_context.method_type
            raise "Method context must have `forwarded_arg_type` if `...` node appears in it"
          else
            # Skips type checking forwarded argument because the method type is not given
          end
        when true
          # Skip type checking forwarded argument because the method is untyped function
        else
          params, _block = forward_arg_type

          checker.with_context(self_type: self_type, instance_type: context.module_context.instance_type, class_type: context.module_context.module_type, constraints: constraints) do
            result = checker.check_method_params(
              :"... (argument forwarding)",
              Subtyping::Relation.new(
                sub_type: forwarded_args.params,
                super_type: params
              )
            )

            if result.failure?
              errors.push(
                Diagnostic::Ruby::IncompatibleArgumentForwarding.new(
                  method_name: method_name,
                  node: forwarded_args.node,
                  params_pair: [params, forwarded_args.params],
                  result: result
                )
              )
            end
          end
        end
      end

      constr
    end

    def try_method_type(node, receiver_type:, method_name:, method_overload:, arguments:, block_params:, block_body:, tapp:, hint:)
      constr = self

      method_type = method_overload.method_type
      decls = method_overload.method_decls(method_name).to_set

      if tapp && type_args = tapp.types?(module_context.nesting, checker, [])
        type_arity = method_type.type_params.size
        type_param_names = method_type.type_params.map(&:name)

        # Explicit type application
        if type_args.size == type_arity
          # @type var args_: Array[AST::Types::t]
          args_ = []

          type_args.each_with_index do |type, index|
            param = method_type.type_params.fetch(index)

            if upper_bound = param.upper_bound
              if result = no_subtyping?(sub_type: type.value, super_type: upper_bound)
                args_ << AST::Builtin.any_type
                constr.typing.add_error(
                  Diagnostic::Ruby::TypeArgumentMismatchError.new(
                    type_arg: type.value,
                    type_param: param,
                    result: result,
                    location: type.location
                  )
                )
              else
                args_ << type.value
              end
            else
              args_ << type.value
            end
          end

          method_type = method_type.instantiate(Interface::Substitution.build(type_param_names, args_))
        else
          if type_args.size > type_arity
            type_args.drop(type_arity).each do |type_arg|
              constr.typing.add_error(
                Diagnostic::Ruby::UnexpectedTypeArgument.new(
                  type_arg: type_arg.value,
                  method_type: method_type,
                  location: type_arg.location
                )
              )
            end
          end

          if type_args.size < type_arity
            constr.typing.add_error(
              Diagnostic::Ruby::InsufficientTypeArgument.new(
                node: tapp.node,
                type_args: type_args.map(&:value),
                method_type: method_type
              )
            )
          end

          method_type = method_type.instantiate(
            Interface::Substitution.build(
              type_param_names,
              Array.new(type_param_names.size, AST::Builtin.any_type)
            )
          )
        end

        type_params = [] #: Array[Interface::TypeParam]
        type_param_names.clear
      else
        # Infer type application
        type_params, instantiation = Interface::TypeParam.rename(method_type.type_params)
        type_param_names = type_params.map(&:name)
        method_type = method_type.instantiate(instantiation)
      end

      constr = constr.with(
        context: context.with(
          variable_context: TypeInference::Context::TypeVariableContext.new(
            type_params,
            parent_context: context.variable_context
          )
        )
      )

      variance = Subtyping::VariableVariance.from_method_type(method_type)
      constraints = Subtyping::Constraints.new(unknowns: type_params.map(&:name))
      ccontext = Subtyping::Constraints::Context.new(
        self_type: self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type,
        variance: variance
      )

      upper_bounds = {} #: Hash[Symbol, AST::Types::t]

      type_params.each do |param|
        if ub = param.upper_bound
          constraints.add(param.name, super_type: ub, skip: true)
          upper_bounds[param.name] = ub
        end
      end

      checker.push_variable_bounds(upper_bounds) do
        # @type block: [TypeInference::MethodCall::t, TypeConstruction]

        # @type var errors: Array[Diagnostic::Ruby::Base]
        errors = []

        if method_type.type.params
          args = TypeInference::SendArgs.new(node: node, arguments: arguments, type: method_type)
          constr = constr.type_check_args(
            method_name,
            args,
            constraints,
            errors
          )
        else
          constr = constr.type_check_untyped_args(arguments)
        end

        if block_params
          # block is given

          # @type var node: Parser::AST::Node & Parser::AST::_BlockNode

          block_annotations = source.annotations(block: node, factory: checker.factory, context: nesting)
          block_params_ = TypeInference::BlockParams.from_node(block_params, annotations: block_annotations)

          if method_type.block
            fvs = method_type.type.return_type.free_variables.each.with_object(Set[]) do |var, fvs| #$ Set[Symbol]
              if var.is_a?(Symbol)
                fvs << var
              end
            end

            if hint && !fvs.empty?
              if hint.free_variables.subset?(self_type.free_variables)
                if check_relation(sub_type: method_type.type.return_type, super_type: hint, constraints: constraints).success?
                  method_type, solved, s = apply_solution(errors, node: node, method_type: method_type) do
                    constraints.solution(checker, variables: fvs, context: ccontext)
                  end
                end

                method_type.block or raise
              end
            end

            # Method accepts block
            pairs = block_params_&.zip(method_type.block.type.params, nil, factory: checker.factory)

            if block_params_ && pairs
              # Block parameters are compatible with the block type
              block_constr = constr.for_block(
                block_body,
                block_params: block_params_,
                block_param_hint: method_type.block.type.params,
                block_next_type: method_type.block.type.return_type,
                block_block_hint: nil,
                block_annotations: block_annotations,
                block_self_hint: method_type.block.self_type,
                node_type_hint: method_type.type.return_type
              )

              block_constr = block_constr.with_new_typing(
                block_constr.typing.new_child()
              )

              block_constr.typing.cursor_context.set_body_context(node, block_constr.context)

              pairs.each do |param, type|
                case param
                when TypeInference::BlockParams::Param
                  _, block_constr = block_constr.synthesize(param.node, hint: param.type || type)

                  if param.type
                    check_relation(sub_type: type, super_type: param.type, constraints: constraints).else do |result|
                      error = Diagnostic::Ruby::IncompatibleAssignment.new(
                        node: param.node,
                        lhs_type: param.type,
                        rhs_type: type,
                        result: result
                      )
                      errors << error
                    end
                  end
                when TypeInference::BlockParams::MultipleParam
                  param.each_param do |p|
                    _, block_constr = block_constr.synthesize(p.node, hint: p.type || type)

                    if p.type
                      check_relation(sub_type: type, super_type: p.type, constraints: constraints).else do |result|
                        error = Diagnostic::Ruby::IncompatibleAssignment.new(
                          node: p.node,
                          lhs_type: p.type,
                          rhs_type: type,
                          result: result
                        )
                        errors << error
                      end
                    end
                  end

                  _, block_constr = block_constr.add_typing(param.node, type: type)
                end
              end

              method_type, solved, s = apply_solution(errors, node: node, method_type: method_type) {
                fvs_ = Set[] #: Set[AST::Types::variable]

                fvs_.merge(method_type.type.params.free_variables) if method_type.type.params
                fvs_.merge(method_type.block.type.params.free_variables) if method_type.block.type.params
                (method_type.type.return_type.free_variables + method_type.block.type.return_type.free_variables).each do |var|
                  if var.is_a?(Symbol)
                    if constraints.unknown?(var)
                      unless constraints.has_constraint?(var)
                        fvs_.delete(var)
                      end
                    end
                  end
                end

                constraints.solution(checker, variables: fvs_, context: ccontext)
              }

              method_type.block or raise

              if solved
                # Ready for type check the body of the block
                block_constr = block_constr.update_type_env {|env| env.subst(s) }
                block_constr = block_constr.update_context {|context|
                  context.with(
                    self_type: context.self_type.subst(s),
                    type_env: context.type_env.subst(s),
                    block_context: context.block_context&.subst(s),
                    break_context: context.break_context&.subst(s)
                  )
                }

                block_body_type = block_constr.synthesize_block(
                  node: node,
                  block_body: block_body,
                  block_type_hint: method_type.block.type.return_type
                )

                if method_type.block && method_type.block.self_type
                  block_body_type = block_body_type.subst(
                    Interface::Substitution.build(
                      [],
                      [],
                      self_type: method_type.block.self_type,
                      module_type: singleton_type(method_type.block.self_type) || AST::Builtin.top_type,
                      instance_type: instance_type(method_type.block.self_type) || AST::Builtin.top_type
                    )
                  )
                end

                result = check_relation(sub_type: block_body_type,
                                        super_type: method_type.block.type.return_type,
                                        constraints: constraints)

                if result.success?
                  # Successfully type checked the body
                  method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) do
                    constraints.solution(checker, variables: type_param_names, context: ccontext)
                  end
                  method_type = eliminate_vars(method_type, type_param_names) unless solved

                  return_type = method_type.type.return_type
                  if break_type = block_annotations.break_type
                    return_type = union_type(break_type, return_type)
                  end
                else
                  # The block body has incompatible type
                  errors << Diagnostic::Ruby::BlockBodyTypeMismatch.new(
                    node: node,
                    expected: method_type.block.type.return_type,
                    actual: block_body_type,
                    result: result
                  )

                  method_type = eliminate_vars(method_type, type_param_names)
                  return_type = method_type.type.return_type
                end

                block_constr.typing.save!
              else
                # Failed to infer the type of block parameters
                constr.type_block_without_hint(node: node, block_annotations: block_annotations, block_params: block_params_, block_body: block_body) do |error|
                  errors << error
                end

                method_type = eliminate_vars(method_type, type_param_names)
                return_type = method_type.type.return_type
              end
            else
              # Block parameters are unsupported syntax
              errors << Diagnostic::Ruby::UnsupportedSyntax.new(
                node: block_params,
                message: "Unsupported block params pattern, probably masgn?"
              )

              method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) {
                constraints.solution(checker, variables: type_param_names, context: ccontext)
              }
              method_type = eliminate_vars(method_type, type_param_names) unless solved

              return_type = method_type.type.return_type
            end
          else
            if args
              # Block is given but method doesn't accept
              #
              constr.type_block_without_hint(node: node, block_annotations: block_annotations, block_params: block_params_, block_body: block_body) do |error|
                errors << error
              end

              case node.children[0].type
              when :super, :zsuper
                unless method_context!.super_method
                  errors << Diagnostic::Ruby::UnexpectedSuper.new(
                    node: node.children[0],
                    method: method_name
                  )
                end
              else
                errors << Diagnostic::Ruby::UnexpectedBlockGiven.new(
                  node: node,
                  method_type: method_type
                )
              end

              method_type = eliminate_vars(method_type, type_param_names)
              return_type = method_type.type.return_type
            else
              if block_body
                block_annotations = source.annotations(block: node, factory: checker.factory, context: nesting)
                type_block_without_hint(
                  node: node,
                  block_annotations: block_annotations,
                  block_params: TypeInference::BlockParams.from_node(block_params, annotations: block_annotations),
                  block_body: block_body
                )
              end
            end
          end
        else
          # Block syntax is not given
          if args
            arg = args.block_pass_arg

            case
            when forwarded_args_node = args.forwarded_args_node
              case forward_arg_type = method_context!.forward_arg_type
              when nil
                if method_context!.method_type
                  raise "Method context must have `forwarded_arg_type` if `...` node appears in it"
                else
                  # Skips type checking forwarded argument because the method type is not given
                end
              when true
                # Skip type checking because it's untyped function
              else
                _, block = forward_arg_type

                method_block_type = method_type.block&.to_proc_type || AST::Builtin.nil_type
                forwarded_block_type = block&.to_proc_type || AST::Builtin.nil_type

                if result = constr.no_subtyping?(sub_type: forwarded_block_type, super_type: method_block_type)
                  errors << Diagnostic::Ruby::IncompatibleArgumentForwarding.new(
                    method_name: method_name,
                    node: forwarded_args_node,
                    block_pair: [block, method_type.block],
                    result: result
                  )
                end
              end

            when arg.compatible?
              if arg.node
                # Block pass (&block) is given
                node_type, constr = constr.synthesize(arg.node, hint: arg.node_type)

                nil_given =
                  constr.check_relation(sub_type: node_type, super_type: AST::Builtin.nil_type).success? &&
                    !node_type.is_a?(AST::Types::Any)

                if nil_given
                  # nil is given ==> no block arg node is given
                  method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) {
                    constraints.solution(checker, variables: method_type.free_variables, context: ccontext)
                  }
                  method_type = eliminate_vars(method_type, type_param_names) unless solved

                  # Passing no block
                  errors << Diagnostic::Ruby::RequiredBlockMissing.new(
                    node: node,
                    method_type: method_type
                  )
                else
                  # non-nil value is given
                  constr.check_relation(sub_type: node_type, super_type: arg.node_type, constraints: constraints).else do |result|
                    errors << Diagnostic::Ruby::BlockTypeMismatch.new(
                      node: arg.node,
                      expected: arg.node_type,
                      actual: node_type,
                      result: result
                    )
                  end

                  method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) {
                    constraints.solution(checker, variables: method_type.free_variables, context: ccontext)
                  }
                  method_type = eliminate_vars(method_type, type_param_names) unless solved
                end
              else
                # Block is not given
                method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) {
                  constraints.solution(checker, variables: method_type.free_variables, context: ccontext)
                }
                method_type = eliminate_vars(method_type, type_param_names) unless solved
              end

              return_type = method_type.type.return_type

            when arg.block_missing?
              # Block is required but not given
              method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) {
                constraints.solution(checker, variables: method_type.free_variables, context: ccontext)
              }

              method_type = eliminate_vars(method_type, type_param_names) unless solved
              return_type = method_type.type.return_type

              errors << Diagnostic::Ruby::RequiredBlockMissing.new(
                node: node,
                method_type: method_type
              )

            when arg.unexpected_block?
              # Unexpected block pass node is given

              arg.node or raise

              method_type, solved, _ = apply_solution(errors, node: node, method_type: method_type) {
                constraints.solution(checker, variables: method_type.free_variables, context: ccontext)
              }
              method_type = eliminate_vars(method_type, type_param_names) unless solved
              return_type = method_type.type.return_type

              node_type, constr = constr.synthesize(arg.node)

              unless constr.check_relation(sub_type: node_type, super_type: AST::Builtin.nil_type).success?
                errors << Diagnostic::Ruby::UnexpectedBlockGiven.new(
                  node: node,
                  method_type: method_type
                )
              end
            end
          end
        end

        call = if errors.empty?
                 TypeInference::MethodCall::Typed.new(
                   node: node,
                   context: context.call_context,
                   receiver_type: receiver_type,
                   method_name: method_name,
                   actual_method_type: method_type,
                   return_type: return_type || method_type.type.return_type,
                   method_decls: decls
                 )
               else
                 TypeInference::MethodCall::Error.new(
                   node: node,
                   context: context.call_context,
                   receiver_type: receiver_type,
                   method_name: method_name,
                   return_type: return_type || method_type.type.return_type,
                   method_decls: decls,
                   errors: errors
                 )
               end

        constr = constr.with(
          context: constr.context.with(
            variable_context: context.variable_context
          )
        )

        [
          call,
          constr
        ]
      end
    end

    def type_check_argument(node, type:, constraints:, report_node: node, errors:)
      check(node, type, constraints: constraints) do |expected, actual, result|
        errors << Diagnostic::Ruby::ArgumentTypeMismatch.new(
            node: report_node,
            expected: expected,
            actual: actual,
            result: result
          )
      end
    end

    def type_block_without_hint(node:, block_annotations:, block_params:, block_body:)
      unless block_params
        Diagnostic::Ruby::UnsupportedSyntax.new(
          node: node.children[1],
          message: "Unsupported block params pattern, probably masgn?"
        ).tap do |error|
          if block_given?
            yield error
          else
            typing.add_error(error)
          end
        end

        block_params = TypeInference::BlockParams.new(leading_params: [], optional_params: [], rest_param: nil, trailing_params: [], block_param: nil)
      end

      block_constr = for_block(
        block_body,
        block_params: block_params,
        block_param_hint: nil,
        block_next_type: nil,
        block_block_hint: nil,
        block_annotations: block_annotations,
        block_self_hint: nil,
        node_type_hint: nil
      )

      block_constr.typing.cursor_context.set_body_context(node, block_constr.context)

      block_params.params.each do |param|
        param.each_param do |param|
          _, block_constr = block_constr.synthesize(param.node, hint: param.type)
        end
      end

      block_type = block_constr.synthesize_block(node: node, block_type_hint: nil, block_body: block_body)

      if expected_block_type = block_constr.block_context!.body_type
        block_constr.check_relation(sub_type: block_type, super_type: expected_block_type).else do |result|
          Diagnostic::Ruby::BlockBodyTypeMismatch.new(
            node: node,
            expected: expected_block_type,
            actual: block_type,
            result: result
          ).tap do |error|
            if block_given?
              yield error
            else
              block_constr.typing.add_error(error)
            end
          end
        end
      end
    end

    def set_up_block_mlhs_params_env(node, type, hash, &block)
      if arrayish = try_convert_to_array(type)
        masgn = TypeInference::MultipleAssignment.new()
        assignments = masgn.expand(node, arrayish, false) or raise "#{arrayish} is expected to be array-ish"
        assignments.leading_assignments.each do |pair|
          node, type = pair

          if node.type == :arg
            hash[node.children[0]] = type
          else
            set_up_block_mlhs_params_env(node, type, hash, &block)
          end
        end
      else
        yield node, type
      end
    end

    def for_block(body_node, block_params:, block_param_hint:, block_next_type:, block_block_hint:, block_annotations:, node_type_hint:, block_self_hint:)
      block_param_pairs = block_param_hint && block_params.zip(block_param_hint, block_block_hint, factory: checker.factory)

      # @type var param_types_hash: Hash[Symbol?, AST::Types::t]
      param_types_hash = {}
      if block_param_pairs
        block_param_pairs.each do |param, type|
          case param
          when TypeInference::BlockParams::Param
            var_name = param.var
            param_types_hash[var_name] = type
          when TypeInference::BlockParams::MultipleParam
            set_up_block_mlhs_params_env(param.node, type, param_types_hash) do |error_node, non_array_type|
              Steep.logger.fatal { "`#{non_array_type}#to_ary` returns non-array-ish type" }
              annotation_types = param.variable_types()
              each_descendant_node(error_node) do |n|
                if n.type == :arg
                  name = n.children[0]
                  param_types_hash[name] = annotation_types[name] || AST::Builtin.any_type
                end
              end
            end
          end
        end
      else
        block_params.each do |param|
          case param
          when TypeInference::BlockParams::Param
            var_name = param.var
            param_types_hash[var_name] = param.type || AST::Builtin.any_type
          when TypeInference::BlockParams::MultipleParam
            param.each_param do |p|
              param_types_hash[p.var] = p.type || AST::Builtin.any_type
            end
          end
        end
      end

      param_types_hash.delete_if {|name, _| name && SPECIAL_LVAR_NAMES.include?(name) }

      param_types = param_types_hash.each.with_object({}) do |pair, hash| #$ Hash[Symbol, [AST::Types::t, AST::Types::t?]]
        name, type = pair
        # skip unnamed arguments `*`, `**` and `&`
        next if name.nil?
        hash[name] = [type, nil]
      end

      pins = context.type_env.pin_local_variables(nil)

      type_env = context.type_env
      type_env = type_env.invalidate_pure_node(Parser::AST::Node.new(:self)) if block_self_hint || block_annotations.self_type
      type_env = type_env.merge(local_variable_types: pins)
      type_env = type_env.merge(local_variable_types: param_types)
      type_env = TypeInference::TypeEnvBuilder.new(
        if self_binding = block_annotations.self_type || block_self_hint
          definition =
            case self_binding
            when AST::Types::Name::Instance
              checker.factory.definition_builder.build_instance(self_binding.name)
            when AST::Types::Name::Singleton
              checker.factory.definition_builder.build_singleton(self_binding.name)
            end

          if definition
            TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableDefinition.new(definition, checker.factory)
          end
        end,
        TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(block_annotations).merge!.on_duplicate! do |name, outer_type, inner_type|
          next if outer_type.is_a?(AST::Types::Var) || inner_type.is_a?(AST::Types::Var)
          next unless body_node

          if result = no_subtyping?(sub_type: outer_type, super_type: inner_type)
            typing.add_error Diagnostic::Ruby::IncompatibleAnnotation.new(
              node: body_node,
              var_name: name,
              result: result,
              relation: result.relation
            )
          end
        end
      ).build(type_env)

      break_type = if block_annotations.break_type
                     union_type(node_type_hint, block_annotations.break_type)
                   else
                     node_type_hint
                   end

      block_context = TypeInference::Context::BlockContext.new(
        body_type: block_annotations.block_type
      )
      break_context = TypeInference::Context::BreakContext.new(
        break_type: break_type || AST::Builtin.any_type,
        next_type: block_next_type || AST::Builtin.any_type
      )

      self_type = block_self_hint || self.self_type
      module_context = self.module_context

      if implements = block_annotations.implement_module_annotation
        module_context = default_module_context(implements.name, nesting: nesting)
        self_type = module_context.module_type
      end

      if annotation_self_type = block_annotations.self_type
        self_type = annotation_self_type
      end

      # self_type here means the top-level `self` type because of the `Interface::Builder` implementation
      if self_type
        self_type = expand_self(self_type)
      end

      self.class.new(
        checker: checker,
        source: source,
        annotations: annotations.merge_block_annotations(block_annotations),
        typing: typing,
        context: TypeInference::Context.new(
          block_context: block_context,
          method_context: method_context,
          module_context: module_context,
          break_context: break_context,
          self_type: self_type,
          type_env: type_env,
          call_context: self.context.call_context,
          variable_context: variable_context
        )
      )
    end

    def synthesize_block(node:, block_type_hint:, block_body:)
      if block_body
        body_type, _, context = synthesize(block_body, hint: block_context&.body_type || block_type_hint)

        if annotated_body_type = block_context&.body_type
          if result = no_subtyping?(sub_type: body_type, super_type: annotated_body_type)
            typing.add_error(
              Diagnostic::Ruby::BlockBodyTypeMismatch.new(
                node: node,
                expected: annotated_body_type,
                actual: body_type,
                result: result
              )
            )
          end
          body_type = annotated_body_type
        end

        range = block_body.loc.expression.end_pos..node.loc.end.begin_pos
        typing.cursor_context.set(range, context)

        body_type
      else
        AST::Builtin.nil_type
      end
    end

    def nesting
      module_context&.nesting
    end

    def absolute_name(name)
      checker.factory.absolute_type_name(name, context: nesting)
    end

    def union_type(*types)
      raise if types.empty?
      AST::Types::Union.build(types: types.compact)
    end

    def union_type_unify(*types)
      types = types.reject {|t| t.is_a?(AST::Types::Bot) }

      if types.empty?
        AST::Types::Bot.instance
      else
        types.inject do |type1, type2|
          next type2 if type1.is_a?(AST::Types::Any)
          next type1 if type2.is_a?(AST::Types::Any)

          unless no_subtyping?(sub_type: type1, super_type: type2)
            # type1 <: type2
            next type2
          end

          unless no_subtyping?(sub_type: type2, super_type: type1)
            # type2 <: type1
            next type1
          end

          union_type(type1, type2)
        end
      end
    end

    def union_of_tuple_to_tuple_of_union(type)
      if type.types.all? {|ty| ty.is_a?(AST::Types::Tuple) }
        # @type var tuples: Array[AST::Types::Tuple]
        tuples = _ = type.types

        max = tuples.map {|tup| tup.types.size }.max or raise

        # @type var tuple_types_array: Array[Array[AST::Types::t]]
        tuple_types_array = tuples.map do |tup|
          if tup.types.size == max
            tup.types
          else
            tup.types + Array.new(max - tup.types.size, AST::Builtin.nil_type)
          end
        end

        # @type var tuple_elems_array: Array[Array[AST::Types::t]]
        tuple_elems_array = tuple_types_array.transpose
        AST::Types::Tuple.new(
          types: tuple_elems_array.map {|types| union_type_unify(*types) }
        )
      end
    end

    def validate_method_definitions(node, module_name)
      module_name_1 = module_name.name
      module_entry = checker.factory.env.normalized_module_class_entry(module_name_1) or raise
      member_decl_count = module_entry.each_decl.count do |decl|
        case decl
        when RBS::AST::Declarations::Base
          decl.each_member.count > 0
        else
          false
        end
      end

      return unless member_decl_count == 1

      expected_instance_method_names = (module_context.instance_definition&.methods || {}).each.with_object(Set[]) do |(name, method), set|
        if method.implemented_in
          if method.implemented_in == module_context.instance_definition&.type_name
            set << name
          end
        end
      end
      expected_module_method_names = (module_context.module_definition&.methods || {}).each.with_object(Set[]) do |(name, method), set|
        if name != :new
          if method.implemented_in
            if method.implemented_in == module_context.module_definition&.type_name
              set << name
            end
          end
        end
      end

      expected_instance_method_names.each do |method_name|
        case
        when module_context.defined_instance_methods.include?(method_name)
          # ok
        when annotations.instance_dynamics.include?(method_name)
          # ok
        else
          if module_name.name == module_context&.class_name
            typing.add_error(
              Diagnostic::Ruby::MethodDefinitionMissing.new(
                node: node,
                module_name: module_name.name,
                kind: :instance,
                missing_method: method_name
              )
            )
          end
        end
      end
      expected_module_method_names.each do |method_name|
        case
        when module_context.defined_module_methods.include?(method_name)
          # ok
        when annotations.module_dynamics.include?(method_name)
          # ok
        else
          if module_name.name == module_context&.class_name
            typing.add_error(
              Diagnostic::Ruby::MethodDefinitionMissing.new(node: node,
                                                            module_name: module_name.name,
                                                            kind: :module,
                                                            missing_method: method_name)
            )
          end
        end
      end

      annotations.instance_dynamics.each do |method_name|
        unless expected_instance_method_names.member?(method_name)
          typing.add_error(
            Diagnostic::Ruby::UnexpectedDynamicMethod.new(node: node,
                                                          module_name: module_name.name,
                                                          method_name: method_name)
          )
        end
      end
      annotations.module_dynamics.each do |method_name|
        unless expected_module_method_names.member?(method_name)
          typing.add_error(
            Diagnostic::Ruby::UnexpectedDynamicMethod.new(node: node,
                                                          module_name: module_name.name,
                                                          method_name: method_name)
          )
        end
      end
    end

    def fallback_to_any(node)
      if block_given?
        typing.add_error yield
      else
        typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
      end

      add_typing node, type: AST::Builtin.any_type
    end

    def namespace_module?(node)
      # @type var nodes: Array[Parser::AST::Node]
      nodes =
        case node.type
        when :class, :module
          node.children.last&.yield_self {|child|
            if child.type == :begin
              child.children
            else
              [child]
            end
          } || []
        else
          return false
        end

      !nodes.empty? && nodes.all? {|child| child.type == :class || child.type == :module}
    end

    def type_any_rec(node, only_children: false)
      add_typing node, type: AST::Builtin.any_type unless only_children

      each_child_node(node) do |child|
        type_any_rec(child)
      end

      Pair.new(type: AST::Builtin.any_type, constr: self)
    end

    def unwrap(type)
      checker.factory.unwrap_optional(type) || AST::Types::Bot.instance
    end

    def deep_expand_alias(type)
      checker.factory.deep_expand_alias(type)
    end

    def flatten_union(type)
      checker.factory.flatten_union(type)
    end

    def select_flatten_types(type, &block)
      types = flatten_union(deep_expand_alias(type) || type)
      types.select(&block)
    end

    def partition_flatten_types(type, &block)
      types = flatten_union(deep_expand_alias(type) || type)
      types.partition(&block)
    end

    def flatten_array_elements(type)
      flatten_union(deep_expand_alias(type) || type).flat_map do |type|
        if AST::Builtin::Array.instance_type?(type)
          # @type var type: AST::Types::Name::Instance
          type.args
        else
          [type]
        end
      end
    end

    def expand_alias(type, &block)
      typ = checker.factory.expand_alias(type)
      if block
        yield(typ)
      else
        typ
      end
    end

    def test_literal_type(literal, hint)
      if hint
        case hint
        when AST::Types::Any
          nil
        else
          literal_type = AST::Types::Literal.new(value: literal)
          if check_relation(sub_type: literal_type, super_type: hint).success?
            hint
          end
        end
      end
    end

    def to_instance_type(type, args: nil)
      args = args || case type
                     when AST::Types::Name::Singleton
                       decl = checker.factory.env.normalized_module_class_entry(type.name) or raise
                       decl.type_params.each.map { AST::Builtin.any_type }
                     else
                       raise "unexpected type to to_instance_type: #{type}"
                     end

      AST::Types::Name::Instance.new(name: type.name, args: args)
    end

    def try_tuple_type!(node, hint: nil)
      if node.type == :array
        if node.children.size == 1 && node.children[0]&.type == :splat
          # Skip the array construct
          splat_node = node.children[0] or raise
          splat_value = splat_node.children[0] or raise

          type, constr = try_tuple_type!(splat_value, hint: hint)
          _, constr = constr.add_typing(splat_node, type: AST::Types::Any.instance)
          return constr.add_typing(node, type: type)
        end
        if hint.nil? || hint.is_a?(AST::Types::Tuple)
          typing.new_child() do |child_typing|
            if pair = with_new_typing(child_typing).try_tuple_type(node, hint)
              return pair.with(constr: pair.constr.save_typing)
            end
          end
        end
      end

      synthesize(node, hint: hint)
    end

    def try_tuple_type(array_node, hint)
      raise unless array_node.type == :array

      constr = self #: TypeConstruction
      element_types = [] #: Array[AST::Types::t]

      array_node.children.each_with_index do |child, index|
        if child.type == :splat
          type, constr = constr.synthesize(child.children[0])
          typing.add_typing(child, type, nil)
          if converted_type = try_convert(type, :to_a)
            if converted_type.is_a?(AST::Types::Tuple)
              element_types.push(*converted_type.types)
            else
              # The converted_type may be an array, which cannot be used to construct a tuple type
              return
            end
          else
            element_types << type
          end
        else
          child_hint =
            if hint
              hint.types[index]
            end

          type, constr = constr.synthesize(child, hint: child_hint)
          element_types << type
        end
      end

      constr.add_typing(array_node, type: AST::Types::Tuple.new(types: element_types))
    end

    def try_convert(type, method)
      if shape = calculate_interface(type, private: false)
        if entry = shape.methods[method]
          method_type = entry.method_types.find do |method_type|
            method_type.type.params.nil? || method_type.type.params.optional?
          end

          method_type.type.return_type if method_type
        end
      end
    end

    def try_convert_to_array(type)
      if arrayish = arrayish_type?(type, untyped_is: true) || semantically_arrayish_type?(type)
        arrayish
      else
        if converted = try_convert(type, :to_ary)
          if arrayish_type?(converted, untyped_is: true) || semantically_arrayish_type?(type)
            converted
          end
        else
          AST::Types::Tuple.new(types: [type])
        end
      end
    end

    def arrayish_type?(type, untyped_is: false)
      case type
      when AST::Types::Any
        if untyped_is
          type
        end
      when AST::Types::Name::Instance
        if AST::Builtin::Array.instance_type?(type)
          type
        end
      when AST::Types::Tuple
        type
      when AST::Types::Name::Alias
        if t = checker.factory.deep_expand_alias(type)
          arrayish_type?(t)
        end
      end
    end

    def semantically_arrayish_type?(type)
      union = AST::Types::Union.build(types: flatten_union(type))
      if union.is_a?(AST::Types::Union)
        if tuple = union_of_tuple_to_tuple_of_union(union)
          return tuple
        end
      end

      var = AST::Types::Var.fresh(:Elem)
      array = AST::Builtin::Array.instance_type(var)
      constraints = Subtyping::Constraints.new(unknowns: [])
      constraints.add_var(var.name)

      if (result = check_relation(sub_type: type, super_type: array, constraints: constraints)).success?
        context = Subtyping::Constraints::Context.new(
          variance: Subtyping::VariableVariance.from_type(union_type(type, var)),
          self_type: self_type,
          instance_type: module_context.instance_type,
          class_type: module_context.module_type
        )

        variables = (type.free_variables + [var.name]).filter_map do |name|
          case name
          when Symbol
            name
          end
        end
        subst = constraints.solution(checker, variables: variables, context: context)

        type.subst(subst)
      end
    end

    def try_array_type(node, hint)
      element_hint = hint ? hint.args[0] : nil

      constr = self #: TypeConstruction
      element_types = [] #: Array[AST::Types::t]

      each_child_node(node) do |child|
        case child.type
        when :splat
          type, constr = constr.synthesize(child.children[0], hint: hint)

          type = try_convert(type, :to_a) || type

          case
          when AST::Builtin::Array.instance_type?(type)
            type.is_a?(AST::Types::Name::Instance) or raise
            element_types << type.args.fetch(0)
          when type.is_a?(AST::Types::Tuple)
            element_types.push(*type.types)
          else
            element_types.push(*flatten_array_elements(type))
          end
        else
          type, constr = constr.synthesize(child, hint: element_hint)
          element_types << type
        end
      end

      element_type = AST::Types::Union.build(types: element_types)
      constr.add_typing(node, type: AST::Builtin::Array.instance_type(element_type))
    end

    def type_hash_record(hash_node, record_type)
      raise unless hash_node.type == :hash || hash_node.type == :kwargs

      constr = self #: TypeConstruction

      if record_type
        hints = record_type.elements.dup
      else
        hints = {} #: Hash[AST::Types::Record::key, AST::Types::t]
      end

      elems = {} #: Hash[AST::Types::Record::key, AST::Types::t]

      each_child_node(hash_node) do |child|
        if child.type == :pair
          case child.children[0].type
          when :sym, :int, :str, :true, :false
            key_node = child.children[0] #: Parser::AST::Node
            value_node = child.children[1] #: Parser::AST::Node

            key =
              case key_node.type
              when :sym, :int, :str
                key_node.children[0]
              when :true
                true
              when :false
                false
              end #: AST::Types::Record::key

            _, constr = constr.synthesize(key_node, hint: AST::Types::Literal.new(value: key))

            value_type, constr = constr.synthesize(value_node, hint: hints[key])

            if hints.key?(key)
              hint_type = hints.fetch(key)
              case
              when value_type.is_a?(AST::Types::Any)
                value_type = hints.fetch(key)
              when hint_type.is_a?(AST::Types::Var)
                value_type = value_type
              end
            else
              typing.add_error(
                Diagnostic::Ruby::UnknownRecordKey.new(key: key, node: key_node)
              )
            end

            elems[key] = value_type
          else
            return
          end
        else
          return
        end
      end

      type = AST::Types::Record.new(elements: elems, required_keys: record_type&.required_keys || Set.new(elems.keys))
      constr.add_typing(hash_node, type: type)
    end

    def type_hash(hash_node, hint:)
      if hint
        hint = deep_expand_alias(hint)
      end

      case hint
      when AST::Types::Record
        with_child_typing() do |constr|
          pair = constr.type_hash_record(hash_node, hint)
          if pair
            return pair.with(constr: pair.constr.save_typing)
          end
        end
      when AST::Types::Union
        pair = pick_one_of(hint.types) do |type, constr|
          constr.type_hash(hash_node, hint: type)
        end

        if pair
          return pair
        end
      end

      key_types = [] #: Array[AST::Types::t]
      value_types = [] #: Array[AST::Types::t]

      if hint && AST::Builtin::Hash.instance_type?(hint)
        # @type var hint: AST::Types::Name::Instance
        key_hint, value_hint = hint.args
      end

      hint_hash = AST::Builtin::Hash.instance_type(
        key_hint || AST::Builtin.any_type,
        value_hint || AST::Builtin.any_type
      )

      constr = self #: TypeConstruction

      if hash_node.children.empty?
        key_types << key_hint if key_hint
        value_types << value_hint if value_hint
      else
        hash_node.children.each do |elem|
          case elem.type
          when :pair
            key_node, value_node = elem.children
            key_type, constr = constr.synthesize(key_node, hint: key_hint)
            value_type, constr = constr.synthesize(value_node, hint: value_hint)

            key_types << key_type
            value_types << value_type
          when :kwsplat
            bypass_splat(elem) do |elem_|
              constr.synthesize(elem_, hint: hint_hash).tap do |(type, _)|
                if AST::Builtin::Hash.instance_type?(type)
                  # @type var type: AST::Types::Name::Instance
                  key_types << type.args.fetch(0)
                  value_types << type.args.fetch(1)
                end
              end
            end
          else
            raise
          end
        end
      end

      key_types.reject! {|ty| ty.is_a?(AST::Types::Any) }
      value_types.reject! {|ty| ty.is_a?(AST::Types::Any) }

      key_types << AST::Builtin.any_type if key_types.empty?
      value_types << AST::Builtin.any_type if value_types.empty?

      hash_type = AST::Builtin::Hash.instance_type(
        AST::Types::Union.build(types: key_types),
        AST::Types::Union.build(types: value_types)
      )
      constr.add_typing(hash_node, type: hash_type)
    end

    def pick_one_of(types)
      types.each do |type|
        with_child_typing() do |constr|
          if (type_, constr = yield(type, constr))
            constr.check_relation(sub_type: type_, super_type: type).then do
              constr = constr.save_typing
              return Pair.new(type: type_, constr: constr)
            end
          end
        end
      end

      nil
    end

    def save_typing
      typing.save!
      with_new_typing(typing.parent || raise)
    end

    def type_name(type)
      case type
      when AST::Types::Name::Instance, AST::Types::Name::Singleton
        type.name
      when AST::Types::Literal
        type_name(type.back_type)
      when AST::Types::Tuple
        AST::Builtin::Array.module_name
      when AST::Types::Record
        AST::Builtin::Hash.module_name
      when AST::Types::Proc
        AST::Builtin::Proc.module_name
      when AST::Types::Boolean, AST::Types::Logic::Base
        nil
      end
    end

    def singleton_type(type)
      case type
      when AST::Types::Union
        AST::Types::Union.build(
          types: type.types.map {|t| singleton_type(t) or return }
        )
      when AST::Types::Intersection
        AST::Types::Intersection.build(
          types: type.types.map {|t| singleton_type(t) or return }
        )
      else
        if name = type_name(type)
          AST::Types::Name::Singleton.new(name: name)
        end
      end
    end

    def instance_type(type)
      case type
      when AST::Types::Union
        AST::Types::Union.build(
          types: type.types.map {|t| instance_type(t) or return }
        )
      when AST::Types::Intersection
        AST::Types::Intersection.build(
          types: type.types.map {|t| instance_type(t) or return }
        )
      else
        if name = type_name(type)
          checker.factory.instance_type(name)
        end
      end
    end

    def check_deprecation_global(name, node, location)
      if global_entry = checker.factory.env.global_decls[name]
        if (_, message = AnnotationsHelper.deprecated_annotation?(global_entry.decl.annotations))
          typing.add_error(
            Diagnostic::Ruby::DeprecatedReference.new(
              node: node,
              location: location,
              message: message
            )
          )
        end
      end
    end

    def check_deprecation_constant(name, node, location)
      entry = checker.builder.factory.env.constant_entry(name)

      annotations =
        case entry
        when RBS::Environment::ModuleEntry, RBS::Environment::ClassEntry
          entry.each_decl.flat_map do |decl|
            if decl.is_a?(RBS::AST::Declarations::Base)
              decl.annotations
            else
              []
            end
          end
        when RBS::Environment::ConstantEntry, RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
          if entry.decl.is_a?(RBS::AST::Declarations::Base)
            entry.decl.annotations
          else
            [] #: Array[RBS::AST::Annotation]
          end
        end

      if annotations
        if (_, message = AnnotationsHelper.deprecated_annotation?(annotations))
          typing.add_error(
            Diagnostic::Ruby::DeprecatedReference.new(
              node: node,
              location: location,
              message: message
            )
          )
        end
      end
    end
  end
end
