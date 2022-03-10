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

    def block_context
      context.block_context
    end

    def break_context
      context.break_context
    end

    def self_type
      context.self_type
    end

    def type_env
      context.type_env
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

    def with_updated_context(lvar_env: self.context.lvar_env)
      if lvar_env != self.context.lvar_env
        with(context: self.context.with(lvar_env: lvar_env))
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

    def update_lvar_env
      with_updated_context(lvar_env: yield(context.lvar_env))
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

    def for_new_method(method_name, node, args:, self_type:, definition:)
      annots = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)
      type_env = TypeInference::TypeEnv.new(subtyping: checker,
                                            const_env: module_context&.const_env || self.type_env.const_env)

      self.type_env.const_types.each do |name, type|
        type_env.set(const: name, type: type)
      end

      definition_method_type = if definition
                                 definition.methods[method_name]&.yield_self do |method|
                                   method.method_types
                                     .map {|method_type| checker.factory.method_type(method_type, self_type: self_type, method_decls: Set[]) }
                                     .select {|method_type| method_type.is_a?(Interface::MethodType) }
                                     .inject {|t1, t2| t1 + t2}
                                 end
                               end
      annotation_method_type = annotations.method_type(method_name)

      method_type = annotation_method_type || definition_method_type

      if annots&.return_type && method_type&.type&.return_type
        check_relation(sub_type: annots.return_type, super_type: method_type.type.return_type).else do |result|
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

      method_context = TypeInference::Context::MethodContext.new(
        name: method_name,
        method: definition && definition.methods[method_name],
        method_type: method_type,
        return_type: annots.return_type || method_type&.type&.return_type || AST::Builtin.any_type,
        constructor: false,
        super_method: super_method
      )

      if definition
        definition.instance_variables.each do |name, decl|
          type_env.set(ivar: name, type: checker.factory.type(decl.type))
        end
      end

      type_env = type_env.with_annotations(
        ivar_types: annots.ivar_types,
        const_types: annots.const_types,
        self_type: annots.self_type || self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      )

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: annots.self_type || self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      )

      method_params =
        if method_type
          TypeInference::MethodParams.build(node: node, method_type: method_type)
        else
          TypeInference::MethodParams.empty(node: node)
        end

      method_params.each_param do |param|
        lvar_env = lvar_env.assign(param.name, type: param.var_type, node: param.node) {
          raise "Unexpected assignment error: #{param.name}"
        }
      end

      method_params.errors.each do |error|
        typing.add_error error
      end

      lvar_env = lvar_env.annotate(annots)

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
          lvar_env: lvar_env,
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
        name = nil
        name ||= absolute_name(module_name).yield_self do |absolute_name|
          absolute_name if checker.factory.class_name?(absolute_name) || checker.factory.module_name?(absolute_name)
        end
        name ||= super_name && absolute_name(super_name).yield_self do |absolute_name|
          absolute_name if checker.factory.class_name?(absolute_name) || checker.factory.module_name?(absolute_name)
        end

        if name
          absolute_name_ = name
          entry = checker.factory.env.class_decls[absolute_name_]
          AST::Annotation::Implements::Module.new(
            name: name,
            args: entry.type_params.each.map(&:name)
          )
        end
      end
    end

    def default_module_context(implement_module_name, const_env:, current_namespace:)
      if implement_module_name
        module_name = checker.factory.absolute_type_name(implement_module_name.name, namespace: current_namespace)
        module_args = implement_module_name.args.map {|name| AST::Types::Var.new(name: name) }

        instance_def = checker.factory.definition_builder.build_instance(module_name)
        module_def = checker.factory.definition_builder.build_singleton(module_name)

        instance_type = AST::Types::Name::Instance.new(name: module_name, args: module_args)
        module_type = AST::Types::Name::Singleton.new(name: module_name)

        TypeInference::Context::ModuleContext.new(
          instance_type: instance_type,
          module_type: module_type,
          implement_name: implement_module_name,
          current_namespace: current_namespace,
          const_env: const_env,
          class_name: module_name,
          instance_definition: instance_def,
          module_definition: module_def
        )
      else
        TypeInference::Context::ModuleContext.new(
          instance_type: nil,
          module_type: nil,
          implement_name: nil,
          current_namespace: current_namespace,
          const_env: self.module_context.const_env,
          class_name: self.module_context.class_name,
          module_definition: nil,
          instance_definition: nil
        )
      end
    end

    def for_module(node)
      new_module_name = module_name_from_node(node.children.first) or raise "Unexpected module name: #{node.children.first}"
      new_namespace = nested_namespace_for_module(new_module_name)

      const_context = [new_namespace] + self.module_context.const_env.context
      module_const_env = TypeInference::ConstantEnv.new(factory: checker.factory, context: const_context)

      annots = source.annotations(block: node, factory: checker.factory, current_module: new_namespace)

      implement_module_name = implement_module(module_name: new_module_name, annotations: annots)
      module_context = default_module_context(implement_module_name, const_env: module_const_env, current_namespace: new_namespace)

      unless implement_module_name
        module_context = module_context.update(
          module_type: AST::Builtin::Module.instance_type,
          instance_type: AST::Builtin::BasicObject.instance_type
        )
      end

      if implement_module_name
        module_entry = checker.factory.definition_builder.env.class_decls[implement_module_name.name]

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
                       end
                checker.factory.type(type)
              },
              module_context.instance_type
            ].compact
          )
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

      module_type_env = TypeInference::TypeEnv.build(annotations: annots,
                                                     subtyping: checker,
                                                     const_env: module_const_env,
                                                     signatures: checker.factory.env)

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: module_context.module_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      ).annotate(annots)

      if implement_module_name
        definition = checker.factory.definition_builder.build_instance(implement_module_name.name)
        type_params = definition.type_params_decl.map do |param|
          Interface::TypeParam.new(
            name: param.name,
            upper_bound: checker.factory.type_opt(param.upper_bound),
            variance: param.variance,
            unchecked: param.unchecked?
          )
        end
        variable_context = TypeInference::Context::TypeVariableContext.new(type_params)
      else
        variable_context = TypeInference::Context::TypeVariableContext.empty
      end

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
          lvar_env: lvar_env,
          call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context.class_name),
          variable_context: variable_context
        )
      )
    end

    def with_module_constr(node)
      constr = for_module(node)
      constr.checker.push_variable_bounds(constr.variable_context.upper_bounds) do
        yield constr
      end
    end

    def for_class(node)
      new_class_name = module_name_from_node(node.children.first) or raise "Unexpected class name: #{node.children.first}"
      super_class_name = node.children[1] && module_name_from_node(node.children[1])
      new_namespace = nested_namespace_for_module(new_class_name)

      annots = source.annotations(block: node, factory: checker.factory, current_module: new_namespace)

      const_context = [new_namespace] + self.module_context.const_env.context
      class_const_env = TypeInference::ConstantEnv.new(factory: checker.factory, context: const_context)

      implement_module_name = implement_module(module_name: new_class_name, super_name: super_class_name, annotations: annots)
      module_context = default_module_context(implement_module_name, const_env: class_const_env, current_namespace: new_namespace)

      if implement_module_name
        if super_class_name && implement_module_name.name == absolute_name(super_class_name)
          module_context = module_context.update(instance_definition: nil, module_definition: nil)
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
          upper_bound: type_param.upper_bound&.yield_self {|t| checker.factory.type(t) },
          variance: type_param.variance,
          unchecked: type_param.unchecked?,
          location: type_param.location
        )
      end
      variable_context = TypeInference::Context::TypeVariableContext.new(type_params)

      class_type_env = TypeInference::TypeEnv.build(annotations: annots,
                                                    subtyping: checker,
                                                    const_env: class_const_env,
                                                    signatures: checker.factory.env)

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: module_context.module_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      ).annotate(annots)

      class_body_context = TypeInference::Context.new(
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: module_context.module_type,
        type_env: class_type_env,
        lvar_env: lvar_env,
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

    def with_class_constr(node)
      constr = for_class(node)

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

    def for_sclass(node, type)
      annots = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)

      instance_type = if type.is_a?(AST::Types::Self)
                        context.self_type
                      else
                        type
                      end

      module_type = case instance_type
                    when AST::Types::Name::Singleton
                      type_name = instance_type.name

                      case checker.factory.env.class_decls[type_name]
                      when RBS::Environment::ModuleEntry
                        AST::Builtin::Module.instance_type
                      when RBS::Environment::ClassEntry
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
                            end

      module_definition = case module_type
                          when AST::Types::Name::Singleton
                            type_name = instance_type.name
                            checker.factory.definition_builder.build_singleton(type_name)
                          else
                            nil
                          end

      module_context = TypeInference::Context::ModuleContext.new(
        instance_type: annots.instance_type || instance_type,
        module_type: annots.self_type || annots.module_type || module_type,
        implement_name: nil,
        current_namespace: current_namespace,
        const_env: self.module_context.const_env,
        class_name: self.module_context.class_name,
        module_definition: module_definition,
        instance_definition: instance_definition
      )

      type_env = TypeInference::TypeEnv.build(annotations: annots,
                                              subtyping: checker,
                                              const_env: self.module_context.const_env,
                                              signatures: checker.factory.env)

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: module_context.module_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      ).annotate(annots)

      body_context = TypeInference::Context.new(
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: module_context.module_type,
        type_env: type_env,
        lvar_env: lvar_env,
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

    def for_branch(node, truthy_vars: Set.new, type_case_override: nil, break_context: context.break_context)
      annots = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)

      lvar_env = context.lvar_env

      unless truthy_vars.empty?
        lvar_env = lvar_env.yield_self do |env|
          decls = env.declared_types.each.with_object({}) do |(name, entry), hash|
            if truthy_vars.include?(name)
              hash[name] = entry.update(type: unwrap(entry.type))
            else
              hash[name] = entry
            end
          end

          assignments = env.assigned_types.each.with_object({}) do |(name, entry), hash|
            if truthy_vars.include?(name)
              hash[name] = entry.update(type: unwrap(entry.type))
            else
              hash[name] = entry
            end
          end

          env.update(declared_types: decls, assigned_types: assignments)
        end
      end

      if type_case_override
        lvar_env = type_case_override.inject(lvar_env) do |lvar_env, (name, type)|
          lvar_env.assign!(name, node: node, type: type) do |declared_type, assigned_type, result|
            relation = Subtyping::Relation.new(sub_type: assigned_type, super_type: declared_type)
            typing.add_error(
              Diagnostic::Ruby::IncompatibleTypeCase.new(
                node: node,
                var_name: name,
                relation: relation,
                result: result
              )
            )
          end
        end
      end

      lvar_env = lvar_env.annotate(annots) do |var, outer_type, inner_type, result|
        relation = Subtyping::Relation.new(sub_type: inner_type, super_type: outer_type)
        typing.add_error(
          Diagnostic::Ruby::IncompatibleAnnotation.new(
            node: node,
            var_name: var,
            relation: relation,
            result: result
          )
        )
      end

      type_env = context.type_env

      if type_case_override
        type_env = type_env.with_annotations(
          self_type: self_type,
          instance_type: module_context.instance_type,
          class_type: module_context.module_type
        )
      end

      type_env = type_env.with_annotations(
        ivar_types: annots.ivar_types,
        const_types: annots.const_types,
        gvar_types: {},
        self_type: self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      ) do |var, relation, result|
        typing.add_error(
          Diagnostic::Ruby::IncompatibleAnnotation.new(
            node: node,
            var_name: var,
            relation: relation,
            result: result
          )
        )
      end

      update_context {|context|
        context.with(type_env: type_env,
                     break_context: break_context,
                     lvar_env: lvar_env)
      }
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
                    typing.add_context(range, context: new_pair.constr.context)
                  end
                end
              end

              p = pair.constr.synthesize(last_node, hint: hint)
              last_pair = pair + p
              last_pair.constr.add_typing(node, type: last_pair.type, constr: last_pair.constr)
            else
              add_typing(node, type: AST::Builtin.nil_type)
            end
          end

        when :lvasgn
          yield_self do
            var, rhs = node.children
            name = var

            case name
            when :_, :__any__
              synthesize(rhs, hint: AST::Builtin.any_type).yield_self do |pair|
                add_typing(node, type: AST::Builtin.any_type, constr: pair.constr)
              end
            when :__skip__
              add_typing(node, type: AST::Builtin.any_type)
            else
              if declared_type = context.lvar_env.declared_types[name]&.type
                case hint
                when nil
                  hint = declared_type
                else
                  if check_relation(sub_type: declared_type, super_type: hint).success?
                    # declared_type is compatible with hint and more specific to hint.
                    # This typically happens when hint is untyped, top, or void.
                    hint = declared_type
                  end
                end
              end

              rhs_result = synthesize(rhs, hint: hint)

              constr = rhs_result.constr.update_lvar_env do |lvar_env|
                lvar_env.assign(name, node: node, type: rhs_result.type) do |declared_type, actual_type, result|
                  typing.add_error(
                    Diagnostic::Ruby::IncompatibleAssignment.new(
                      node: node,
                      lhs_type: declared_type,
                      rhs_type: actual_type,
                      result: result
                    )
                  )
                end
              end

              constr.add_typing(node, type: rhs_result.type)
            end
          end

        when :lvar
          yield_self do
            var = node.children[0]
            if (type = context.lvar_env[var])
              add_typing node, type: type
            else
              fallback_to_any(node)
            end
          end

        when :ivasgn
          name = node.children[0]
          value = node.children[1]

          type_ivasgn(name, value, node)

        when :ivar
          yield_self do
            name = node.children[0]
            type = type_env.get(ivar: name) do
              fallback_to_any node
            end
            add_typing(node, type: type)
          end

        when :send
          yield_self do
            if self_class?(node)
              module_type = expand_alias(module_context.module_type)
              type = if module_type.is_a?(AST::Types::Name::Singleton)
                       AST::Types::Name::Singleton.new(name: module_type.name)
                     else
                       module_type
                     end

              add_typing(node, type: type)
            else
              type_send(node, send_node: node, block_params: nil, block_body: nil)
            end
          end

        when :csend
          yield_self do
            pair = if self_class?(node)
                     module_type = expand_alias(module_context.module_type)
                     type = if module_type.is_a?(AST::Types::Name::Singleton)
                              AST::Types::Name::Singleton.new(name: module_type.name)
                            else
                              module_type
                            end
                     add_typing(node, type: type)
                   else
                     type_send(node, send_node: node, block_params: nil, block_body: nil, unwrap: true)
                   end

            lvar_env = context.lvar_env.join(pair.context.lvar_env, context.lvar_env)
            add_typing(node,
                       type: union_type(pair.type, AST::Builtin.nil_type),
                       constr: pair.constr.with_updated_context(lvar_env: lvar_env))
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
            if self_type && method_context&.method
              if super_def = method_context.super_method
                each_child_node(node) do |child|
                  synthesize(child)
                end

                super_method = Interface::Interface::Entry.new(
                  method_types: method_context.super_method.method_types.map {|method_type|
                    decl = TypeInference::MethodCall::MethodDecl.new(
                      method_name: InstanceMethodName.new(type_name: super_def.implemented_in || super_def.defined_in,
                                                          method_name: method_context.name),
                      method_def: super_def
                    )
                    checker.factory.method_type(method_type, self_type: self_type, method_decls: Set[decl])
                  }
                )

                call, constr = type_method_call(node,
                                                receiver_type: self_type,
                                                method_name: method_context.name,
                                                method: super_method,
                                                arguments: node.children,
                                                block_params: nil,
                                                block_body: nil,
                                                topdown_hint: true)

                if call && constr
                  constr.add_call(call)
                else
                  error = Diagnostic::Ruby::UnresolvedOverloading.new(
                    node: node,
                    receiver_type: self_type,
                    method_name: method_context.name,
                    method_types: super_method.method_types
                  )
                  call = TypeInference::MethodCall::Error.new(
                    node: node,
                    context: context.method_context,
                    method_name: method_context.name,
                    receiver_type: self_type,
                    errors: [error]
                  )

                  constr = synthesize_children(node)

                  fallback_to_any(node) { error }
                end
              else
                fallback_to_any node do
                  Diagnostic::Ruby::UnexpectedSuper.new(node: node, method: method_context.name)
                end
              end
            else
              fallback_to_any node
            end
          end

        when :block
          yield_self do
            send_node, params, body = node.children
            if send_node.type == :lambda
              type_lambda(node, params_node: params, body_node: body, type_hint: hint)
            else
              type_send(node, send_node: send_node, block_params: params, block_body: body, unwrap: send_node.type == :csend)
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
              type_lambda(node, params_node: params, body_node: body, type_hint: hint)
            else
              type_send(node, send_node: send_node, block_params: params, block_body: body, unwrap: send_node.type == :csend)
            end
          end

        when :def
          yield_self do
            name, args_node, body_node = node.children

            with_method_constr(
              name,
              node,
              args: args_node.children,
              self_type: module_context&.instance_type,
              definition: module_context&.instance_definition
            ) do |new|
              new.typing.add_context_for_node(node, context: new.context)
              new.typing.add_context_for_body(node, context: new.context)

              new.method_context.tap do |method_context|
                if method_context.method
                  method_name = InstanceMethodName.new(type_name: method_context.method.implemented_in, method_name: name)
                  new.typing.source_index.add_definition(method: method_name, definition: node)
                end
              end

              new = new.synthesize_children(args_node)

              body_pair = if body_node
                            return_type = expand_alias(new.method_context&.return_type)
                            if return_type && !return_type.is_a?(AST::Types::Void)
                              new.check(body_node, return_type) do |_, actual_type, result|
                                typing.add_error(
                                  Diagnostic::Ruby::MethodBodyTypeMismatch.new(
                                    node: node,
                                    expected: new.method_context&.return_type,
                                    actual: actual_type,
                                    result: result
                                  )
                                )
                              end
                            else
                              new.synthesize(body_node)
                            end
                          else
                            return_type = expand_alias(new.method_context&.return_type)
                            if return_type && !return_type.is_a?(AST::Types::Void)
                              result = check_relation(sub_type: AST::Builtin.nil_type, super_type: return_type)
                              if result.failure?
                                typing.add_error(
                                  Diagnostic::Ruby::MethodBodyTypeMismatch.new(
                                    node: node,
                                    expected: new.method_context&.return_type,
                                    actual: AST::Builtin.nil_type,
                                    result: result
                                  )
                                )
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
                  typing.add_context(begin_pos..end_pos, context: body_pair.context)
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
            new.typing.add_context_for_node(node, context: new.context)
            new.typing.add_context_for_body(node, context: new.context)

            new.method_context.tap do |method_context|
              if method_context.method
                name_ = node.children[1]

                method_name =
                  case self_type
                  when AST::Types::Name::Instance
                    InstanceMethodName.new(type_name: method_context.method.implemented_in, method_name: name_)
                  when AST::Types::Name::Singleton
                    SingletonMethodName.new(type_name: method_context.method.implemented_in, method_name: name_)
                  end

                new.typing.source_index.add_definition(method: method_name, definition: node)
              end
            end

            new = new.synthesize_children(args_node)

            each_child_node(node.children[2]) do |arg|
              new.synthesize(arg)
            end

            if node.children[3]
              return_type = expand_alias(new.method_context&.return_type)
              if return_type && !return_type.is_a?(AST::Types::Void)
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

          if module_context
            if node.children[0].type == :self
              module_context.defined_module_methods << node.children[1]
            end
          end

          add_typing(node, type: AST::Builtin::Symbol.instance_type)

        when :return
          yield_self do
            method_return_type = expand_alias(method_context&.return_type)

            if node.children.size > 0
              return_types = node.children.map do |value|
                synthesize(
                  value,
                  hint: if method_return_type.is_a?(AST::Types::Void)
                          nil
                        else
                          method_return_type
                        end
                ).type
              end

              value_type = if return_types.size == 1
                             return_types.first
                           else
                             AST::Builtin::Array.instance_type(union_type(*return_types))
                           end

            else
              value_type = AST::Builtin.nil_type
            end

            if method_return_type
              unless method_return_type.is_a?(AST::Types::Void)
                result = check_relation(sub_type: value_type, super_type: method_return_type)

                if result.failure?
                  typing.add_error(
                    Diagnostic::Ruby::ReturnTypeMismatch.new(
                      node: node,
                      expected: method_context&.return_type,
                      actual: value_type,
                      result: result
                    )
                  )
                end
              end
            end

            add_typing(node, type: AST::Builtin.bottom_type)
          end

        when :break
          value = node.children[0]

          if break_context
            if break_type = break_context.break_type
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

        when :next
          value = node.children[0]

          if break_context
            if next_type = break_context.next_type
              next_type = deep_expand_alias(next_type)

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
            constr = self

            node.children.each do |arg|
              if arg.is_a?(Symbol)
                type = context.lvar_env[arg]

                if type
                  _, constr = add_typing(node, type: type)
                else
                  type = AST::Builtin.any_type
                  _, constr = lvasgn(node, type)
                end
              else
                _, constr = constr.synthesize(arg)
              end
            end

            Pair.new(constr: constr, type: AST::Builtin.any_type)
          end

        when :mlhs
          yield_self do
            constr = self

            node.children.each do |arg|
              _, constr = constr.synthesize(arg)
            end

            Pair.new(constr: constr, type: AST::Builtin.any_type)
          end

        when :arg, :kwarg
          yield_self do
            var = node.children[0]
            type = context.lvar_env[var]

            if type
              add_typing(node, type: type)
            else
              type = AST::Builtin.any_type
              lvasgn(node, type)
            end
          end

        when :optarg, :kwoptarg
          yield_self do
            var = node.children[0]
            rhs = node.children[1]

            var_type = context.lvar_env[var]
            node_type, constr = synthesize(rhs, hint: var_type)

            type = AST::Types::Union.build(types: [var_type, node_type])

            constr_ = constr.update_lvar_env do |env|
              env.assign(var, node: node, type: type) do |declared_type, type, result|
                typing.add_error(
                  Diagnostic::Ruby::IncompatibleAssignment.new(
                    node: node,
                    lhs_type: declared_type,
                    rhs_type: type,
                    result: result
                  )
                )
              end
            end

            add_typing(node, type: type, constr: constr_)
          end

        when :restarg
          yield_self do
            var = node.children[0]
            type = context.lvar_env[var]
            unless type
              if context&.method_context&.method_type
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
            type = context.lvar_env[var]
            unless type
              if context&.method_context&.method_type
                Steep.logger.error { "Unknown variable: #{node}" }
              end
              typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
              type = AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type, AST::Builtin.any_type)
            end

            add_typing(node, type: type)
          end

        when :float
          add_typing(node, type: AST::Builtin::Float.instance_type)

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

          if hint && check_relation(sub_type: ty, super_type: hint).success?
            add_typing(node, type: hint)
          else
            add_typing(node, type: AST::Types::Boolean.new)
          end

        when :hash, :kwargs
          # :kwargs happens for method calls with keyword argument, but the method doesn't have keyword params.
          # Conversion from kwargs to hash happens, and this when-clause is to support it.
          type_hash(node, hint: hint).tap do |pair|
            if pair.type == AST::Builtin::Hash.instance_type(fill_untyped: true)
              case hint
              when AST::Types::Any, AST::Types::Top, AST::Types::Void
                # ok
              when hint == pair.type
                # ok
              else
                pair.constr.typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
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

            name, sup, _ = node.children
            if name.type == :const
              # skip the last constant reference
              if const_parent = name.children[0]
                _, constr = constr.synthesize(const_parent)
              end
            else
              _, constr = constr.synthesize(name)
            end
            _, constr = constr.synthesize(sup) if sup

            with_class_constr(node) do |constructor|
              if module_type = constructor.module_context&.module_type
                _, constructor = constructor.add_typing(name, type: module_type)
              else
                _, constructor = constructor.fallback_to_any(name)
              end

              constructor.typing.source_index.add_definition(
                constant: constructor.module_context.class_name,
                definition: node
              )

              constructor.typing.add_context_for_node(node, context: constructor.context)
              constructor.typing.add_context_for_body(node, context: constructor.context)

              constructor.synthesize(node.children[1]) if node.children[1]
              constructor.synthesize(node.children[2]) if node.children[2]

              if constructor.module_context&.implement_name && !namespace_module?(node)
                constructor.validate_method_definitions(node, constructor.module_context.implement_name)
              end
            end

            add_typing(node, type: AST::Builtin.nil_type)
          end

        when :module
          yield_self do
            constr = self

            name, _ = node.children
            if name.type == :const
              # skip the last constant reference
              if const_parent = name.children[0]
                _, constr = constr.synthesize(const_parent)
              end
            else
              _, constr = constr.synthesize(name)
            end

            with_module_constr(node) do |constructor|
              if module_type = constructor.module_context&.module_type
                _, constructor = constructor.add_typing(name, type: module_type)
              else
                _, constructor = constructor.fallback_to_any(name)
              end

              constructor.typing.source_index.add_definition(
                constant: constructor.module_context.class_name,
                definition: node
              )

              constructor.typing.add_context_for_node(node, context: constructor.context)
              constructor.typing.add_context_for_body(node, context: constructor.context)

              constructor.synthesize(node.children[1]) if node.children[1]

              if constructor.module_context&.implement_name && !namespace_module?(node)
                constructor.validate_method_definitions(node, constructor.module_context.implement_name)
              end
            end

            add_typing(node, type: AST::Builtin.nil_type)
          end

        when :sclass
          yield_self do
            type, constr = synthesize(node.children[0])

            with_sclass_constr(node, type) do |constructor|
              unless constructor
                typing.add_error(
                  Diagnostic::Ruby::UnsupportedSyntax.new(
                    node: node,
                    message: "sclass receiver must be instance type or singleton type, but type given `#{type}`"
                  )
                )
                constr.add_typing(node, type: AST::Builtin.nil_type)
                return
              end

              constructor.typing.add_context_for_node(node, context: constructor.context)
              constructor.typing.add_context_for_body(node, context: constructor.context)

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
          add_typing node, type: AST::Types::Self.new

        when :cbase
          add_typing node, type: AST::Types::Void.new

        when :const
          parent = node.children[0]
          if parent
            _, constr = synthesize(parent)
          else
            constr = self
          end

          const_name = constr.module_name_from_node(node)

          if const_name
            if constant = module_context.const_env.lookup_constant(const_name)
              typing.source_index.add_reference(constant: constant.name, ref: node)
            end

            type = type_env.get(const: const_name) do
              constr.fallback_to_any(node)
            end
            constr.add_typing(node, type: type)
          else
            constr.fallback_to_any(node)
          end

        when :casgn
          yield_self do
            constr = self

            parent = node.children[0]
            _, constr = constr.synthesize(parent) if parent
            const_name = constr.module_name_from_node(node)

            if const_name
              if constant = module_context.const_env.lookup_constant(const_name)
                typing.source_index.add_definition(constant: constant.name, definition: node)
              end

              const_type = type_env.get(const: const_name) {}
              value_type, constr = constr.synthesize(node.children.last, hint: const_type)
              type = type_env.assign(
                const: const_name,
                type: value_type,
                self_type: self_type,
                instance_type: module_context.instance_type,
                class_type: module_context.module_type
              ) do |error|
                if error
                  const_type = type_env.get(const: const_name)
                  typing.add_error(
                    Diagnostic::Ruby::IncompatibleAssignment.new(
                      node: node,
                      lhs_type: const_type,
                      rhs_type: value_type,
                      result: error
                    )
                  )
                else
                  typing.add_error(
                    Diagnostic::Ruby::UnknownConstantAssigned.new(
                      node: node,
                      name: const_name,
                      context: module_context
                    )
                  )
                end
              end

              constr.add_typing(node, type: type)
            else
              _, constr = constr.synthesize(node.children.last)
              constr.fallback_to_any(node)
            end
          end

        when :yield
          if method_context&.method_type
            if method_context.block_type
              block_type = method_context.block_type
              block_type.type.params.flat_unnamed_params.map(&:last).zip(node.children).each do |(type, node)|
                if node && type
                  check(node, type) do |_, rhs_type, result|
                    typing.add_error(
                      Diagnostic::Ruby::IncompatibleAssignment.new(
                        node: node,
                        lhs_type: type,
                        rhs_type: rhs_type,
                        result: result
                      )
                    )
                  end
                end
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
            if method_context&.method
              if method_context.super_method
                types = method_context.super_method.method_types.map {|method_type|
                  checker.factory.method_type(method_type, self_type: self_type, method_decls: Set[]).type.return_type
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
                typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
                add_typing node, type: AST::Builtin::Array.instance_type(AST::Builtin.any_type)
              end
            else
              node_range = node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }

              if hint && !(tuples = select_flatten_types(hint) {|type| type.is_a?(AST::Types::Tuple) }).empty?
                tuples.each do |tuple|
                  typing.new_child(node_range) do |child_typing|
                    if pair = with_new_typing(child_typing).try_tuple_type(node, tuple)
                      return pair.with(constr: pair.constr.save_typing)
                    end
                  end
                end
              end

              if hint && !(arrays = select_flatten_types(hint) {|type| AST::Builtin::Array.instance_type?(type) }).empty?
                arrays.each do |array|
                  typing.new_child(node_range) do |child_typing|
                    pair = with_new_typing(child_typing).try_array_type(node, array)
                    if pair.constr.check_relation(sub_type: pair.type, super_type: hint).success?
                      return pair.with(constr: pair.constr.save_typing)
                    end
                  end
                end
              end

              try_array_type(node, nil)
            end
          end

        when :and
          yield_self do
            left, right = node.children

            left_type, constr = synthesize(left, hint: hint, condition: true)

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing)
            truthy_env, falsey_env = interpreter.eval(env: constr.context.lvar_env, type: left_type, node: left)

            if left_type.is_a?(AST::Types::Logic::Env)
              left_type = left_type.type
            end

            right_type, constr = constr
                                   .update_lvar_env { truthy_env }
                                   .tap {|constr| typing.add_context_for_node(right, context: constr.context) }
                                   .for_branch(right)
                                   .synthesize(right, hint: hint, condition: true)

            truthy_env, _ = interpreter.eval(env: constr.context.lvar_env, type: right_type, node: right)

            env = if right_type.is_a?(AST::Types::Bot)
                    falsey_env
                  else
                    context.lvar_env.join(falsey_env, constr.context.lvar_env)
                  end

            type = case
                   when check_relation(sub_type: left_type, super_type: AST::Types::Boolean.new).success?
                     union_type(left_type, right_type)
                   else
                     union_type(right_type, AST::Builtin.nil_type)
                   end

            type = AST::Types::Logic::Env.new(truthy: truthy_env, falsy: env, type: type) if condition

            add_typing(node,
                       type: type,
                       constr: constr.update_lvar_env { env })
          end

        when :or
          yield_self do
            left, right = node.children

            left_type, constr = synthesize(left, hint: hint, condition: true)

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing)
            truthy_env, falsey_env = interpreter.eval(env: constr.context.lvar_env, type: left_type, node: left)

            if left_type.is_a?(AST::Types::Logic::Env)
              left_type = left_type.type
            end
            left_type, _ = checker.factory.unwrap_optional(left_type)

            right_type, constr = constr
                                   .update_lvar_env { falsey_env }
                                   .tap {|constr| typing.add_context_for_node(right, context: constr.context) }
                                   .for_branch(right)
                                   .synthesize(right, hint: left_type, condition: true)

            _, falsey_env = interpreter.eval(env: falsey_env, type: right_type, node: right)

            env = if right_type.is_a?(AST::Types::Bot)
                    truthy_env
                  else
                    context.lvar_env.join(truthy_env, constr.context.lvar_env)
                  end

            type = case
                   when check_relation(sub_type: left_type, super_type: AST::Builtin.bool_type).success? && !left_type.is_a?(AST::Types::Any)
                     AST::Builtin.bool_type
                   else
                     union_type(left_type, right_type)
                   end

            type = AST::Types::Logic::Env.new(truthy: env, falsy: falsey_env, type: type) if condition

            add_typing(node,
                       type: type,
                       constr: constr.update_lvar_env { env })
          end

        when :if
          cond, true_clause, false_clause = node.children

          cond_type, constr = synthesize(cond, condition: true)
          interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: constr.typing)
          truthy_env, falsey_env = interpreter.eval(env: constr.context.lvar_env, type: cond_type, node: cond)

          if true_clause
            true_pair = constr
                          .update_lvar_env { truthy_env }
                          .for_branch(true_clause)
                          .tap {|constr| typing.add_context_for_node(true_clause, context: constr.context) }
                          .synthesize(true_clause, hint: hint)
          end

          if false_clause
            false_pair = constr
                           .update_lvar_env { falsey_env }
                           .for_branch(false_clause)
                           .tap {|constr| typing.add_context_for_node(false_clause, context: constr.context) }
                           .synthesize(false_clause, hint: hint)
          end

          constr = constr.update_lvar_env do |env|
            envs = []

            if true_pair
              unless true_pair.type.is_a?(AST::Types::Bot)
                envs << true_pair.context.lvar_env
              end
            else
              envs << truthy_env
            end

            if false_pair
              unless false_pair.type.is_a?(AST::Types::Bot)
                envs << false_pair.context.lvar_env
              end
            else
              envs << falsey_env
            end

            env.join(*envs)
          end

          add_typing(node,
                     type: union_type(true_pair&.type || AST::Builtin.nil_type,
                                      false_pair&.type || AST::Builtin.nil_type),
                     constr: constr)

        when :case
          yield_self do
            cond, *whens, els = node.children

            constr = self
            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing)

            if cond
              branch_pairs = []

              cond_type, constr = constr.synthesize(cond)
              _, cond_vars = interpreter.decompose_value(cond)
              unless cond_vars.empty?
                first_var = cond_vars.to_a[0]
                var_node = cond.updated(:lvar, [first_var])
              else
                first_var = nil
                var_node = cond
              end

              when_constr = constr
              whens.each do |clause|
                *tests, body = clause.children

                test_constr = when_constr
                test_envs = []

                tests.each do |test|
                  test_node = test.updated(:send, [test, :===, var_node])
                  test_type, test_constr = test_constr.synthesize(test_node, condition: true)
                  truthy_env, falsy_env = interpreter.eval(type: test_type, node: test_node, env: test_constr.context.lvar_env)
                  truthy_env = cond_vars.inject(truthy_env) do |env, var|
                    env.assign!(var, node: test_node, type: env[first_var])
                  end
                  falsy_env = cond_vars.inject(falsy_env) do |env, var|
                    env.assign!(var, node: test_node, type: env[first_var])
                  end

                  test_envs << truthy_env
                  test_constr = test_constr.update_lvar_env { falsy_env }
                end

                body_constr = when_constr.update_lvar_env {|env| env.except(cond_vars).join(*test_envs) }

                if body
                  branch_pairs << body_constr
                                    .for_branch(body)
                                    .tap {|constr| typing.add_context_for_node(body, context: constr.context) }
                                    .synthesize(body, hint: hint)
                else
                  branch_pairs << Pair.new(type: AST::Builtin.nil_type, constr: body_constr)
                end

                when_constr = test_constr
              end

              if els
                begin_pos = node.loc.else.end_pos
                end_pos = node.loc.end.begin_pos
                typing.add_context(begin_pos..end_pos, context: when_constr.context)

                branch_pairs << when_constr.synthesize(els, hint: hint)
              end

              types = branch_pairs.map(&:type)
              constrs = branch_pairs.map(&:constr)

              if when_constr.context.lvar_env[cond_vars.first].is_a?(AST::Types::Bot)
                # Exhaustive
                if els
                  typing.add_error Diagnostic::Ruby::ElseOnExhaustiveCase.new(node: els, type: cond_type)
                end
              else
                unless els
                  constrs << when_constr
                  types << AST::Builtin.nil_type
                end
              end
            else
              branch_pairs = []

              when_constr = constr
              clause_constr = constr

              whens.each do |clause|
                *tests, body = clause.children

                test_constr = when_constr

                tests.each do |test|
                  test_type, test_constr = test_constr.synthesize(test, condition: true)
                  truthy_env, falsy_env = interpreter.eval(env: test_constr.context.lvar_env, type: test_type, node: test)
                  clause_constr = clause_constr.update_lvar_env { truthy_env }
                  test_constr = test_constr.update_lvar_env { falsy_env }
                end

                when_constr = test_constr

                if body
                  branch_pairs << clause_constr
                                    .for_branch(body)
                                    .tap {|constr| typing.add_context_for_node(body, context: constr.context) }
                                    .synthesize(body, hint: hint)
                else
                  branch_pairs << Pair.new(type: AST::Builtin.nil_type, constr: clause_constr)
                end
              end

              if els
                branch_pairs << when_constr.synthesize(els, hint: hint)
              end

              types = branch_pairs.map(&:type)
              constrs = branch_pairs.map(&:constr)

              unless els
                types << AST::Builtin.nil_type
              end
            end

            constr = constr.update_lvar_env do |env|
              env.join(*constrs.map {|c| c.context.lvar_env })
            end

            add_typing(node, type: union_type(*types), constr: constr)
          end

        when :rescue
          yield_self do
            body, *resbodies, else_node = node.children
            body_pair = synthesize(body, hint: hint) if body

            body_constr = if body_pair
                            self.update_lvar_env do |env|
                              env.join(env, body_pair.context.lvar_env)
                            end
                          else
                            self
                          end

            resbody_pairs = resbodies.map do |resbody|
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

              type_override = {}

              case
              when exn_classes && var_name
                instance_types = exn_types.map do |type|
                  type = expand_alias(type)
                  case
                  when type.is_a?(AST::Types::Name::Singleton)
                    to_instance_type(type)
                  else
                    AST::Builtin.any_type
                  end
                end
                type_override[var_name] = AST::Types::Union.build(types: instance_types)
              when var_name
                type_override[var_name] = AST::Builtin.any_type
              end

              resbody_construction = body_constr.for_branch(resbody, type_case_override: type_override)

              if body
                resbody_construction.synthesize(body, hint: hint)
              else
                Pair.new(constr: body_constr, type: AST::Builtin.nil_type)
              end
            end

            resbody_types = resbody_pairs.map(&:type)
            resbody_envs = resbody_pairs.map {|pair| pair.context.lvar_env }

            if else_node
              else_pair = (body_pair&.constr || self).for_branch(else_node).synthesize(else_node, hint: hint)
              add_typing(node,
                         type: union_type(*[else_pair.type, *resbody_types].compact),
                         constr: update_lvar_env {|env| env.join(*resbody_envs, env) })
            else
              add_typing(node,
                         type: union_type(*[body_pair&.type, *resbody_types].compact),
                         constr: update_lvar_env {|env| env.join(*resbody_envs, (body_pair&.constr || self).context.lvar_env) })
            end
          end

        when :resbody
          yield_self do
            klasses, asgn, body = node.children
            synthesize(klasses) if klasses
            synthesize(asgn) if asgn
            body_type = synthesize(body, hint: hint).type if body
            add_typing(node, type: body_type)
          end

        when :ensure
          yield_self do
            body, ensure_body = node.children
            body_type = synthesize(body).type if body
            synthesize(ensure_body) if ensure_body
            add_typing(node, type: union_type(body_type))
          end

        when :masgn
          type_masgn(node)

        when :for
          yield_self do
            asgn, collection, body = node.children

            collection_type, constr = synthesize(collection)
            collection_type = expand_self(collection_type)

            var_type = case collection_type
                       when AST::Types::Any
                         AST::Types::Any.new
                       else
                         each = calculate_interface(collection_type, private: true).methods[:each]
                         method_type = (each&.method_types || []).find {|type| type.block && type.block.type.params.first_param }
                         method_type&.yield_self do |method_type|
                           method_type.block.type.params.first_param&.type
                         end
                       end

            if var_type
              if body
                body_constr = constr.with_updated_context(
                  lvar_env: constr.context.lvar_env.assign(asgn.children[0], node: asgn, type: var_type)
                )

                typing.add_context_for_body(node, context: body_constr.context)
                _, _, body_context = body_constr.synthesize(body)

                constr = constr.update_lvar_env {|env| env.join(constr.context.lvar_env, body_context.lvar_env) }
              else
                constr = self
              end

              add_typing(node, type: collection_type, constr: constr)
            else
              fallback_to_any(node) do
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
            cond_type, constr = synthesize(cond, condition: true)

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing)
            truthy_env, falsy_env = interpreter.eval(env: constr.context.lvar_env, node: cond, type: cond_type)

            case node.type
            when :while
              body_env, exit_env = truthy_env, falsy_env
            when :until
              exit_env, body_env = truthy_env, falsy_env
            end

            if body
              _, body_constr = constr
                                 .update_lvar_env { body_env.pin_assignments }
                                 .for_branch(body,
                                             break_context: TypeInference::Context::BreakContext.new(
                                               break_type: nil,
                                               next_type: nil
                                             ))
                                 .tap {|constr| typing.add_context_for_node(body, context: constr.context) }
                                 .synthesize(body)

              constr = constr.update_lvar_env {|env| env.join(exit_env, body_constr.context.lvar_env) }
            else
              constr = constr.update_lvar_env { exit_env }
            end

            add_typing(node, type: AST::Builtin.nil_type, constr: constr)
          end

        when :while_post, :until_post
          yield_self do
            cond, body = node.children

            cond_pair = synthesize(cond)

            if body
              for_loop = cond_pair.constr
                           .update_lvar_env {|env| env.pin_assignments }
                           .for_branch(body,
                                       break_context: TypeInference::Context::BreakContext.new(
                                         break_type: nil,
                                         next_type: nil
                                       ))

              typing.add_context_for_node(body, context: for_loop.context)
              body_pair = for_loop.synthesize(body)

              constr = cond_pair.constr.update_lvar_env {|env| env.join(env, body_pair.context.lvar_env) }

              add_typing(node, type: AST::Builtin.nil_type, constr: constr)
            else
              add_typing(node, type: AST::Builtin.nil_type, constr: cond_pair.constr)
            end
          end

        when :irange, :erange
          begin_node, end_node = node.children

          constr = self
          begin_type, constr = if begin_node
                                 constr.synthesize(begin_node)
                               else
                                 [AST::Builtin.nil_type, constr]
                               end
          end_type, constr = if end_node
                               constr.synthesize(end_node)
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

        when :nth_ref, :back_ref
          add_typing(node, type: AST::Builtin::String.instance_type)

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
            when :send
              rhs_ = node.updated(:send,
                                  [
                                    asgn.children[0],
                                    :"#{asgn.children[1]}=",
                                    asgn.children[2],
                                    rhs
                                  ])
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
          each_child_node(node) do |child|
            synthesize(child)
          end

          add_typing(node, type: AST::Builtin.any_type)

        when :gvasgn
          yield_self do
            name, rhs = node.children
            type = type_env.get(gvar: name) do
              fallback_to_any node
            end

            check(rhs, type) do |_, rhs_type, result|
              typing.add_error(
                Diagnostic::Ruby::IncompatibleAssignment.new(
                  node: node,
                  lhs_type: type,
                  rhs_type: rhs_type,
                  result: result
                )
              )
            end
          end

        when :gvar
          yield_self do
            name = node.children.first
            type = type_env.get(gvar: name) do
              typing.add_error Diagnostic::Ruby::FallbackAny.new(node: node)
            end

            add_typing(node, type: type)
          end

        when :block_pass
          yield_self do
            value = node.children[0]

            if hint.is_a?(AST::Types::Proc) && value.type == :sym
              if hint.one_arg?
                # Assumes Symbol#to_proc implementation
                param_type = hint.type.params.required[0]
                case param_type
                when AST::Types::Any
                  type = AST::Types::Any.new
                else
                  interface = calculate_interface(param_type, private: true)
                  method = interface.methods[value.children[0]]
                  if method
                    return_types = method.method_types.select {|method_type|
                      method_type.type.params.empty?
                    }.map {|method_type|
                      method_type.type.return_type
                    }

                    unless return_types.empty?
                      type = AST::Types::Proc.new(
                        type: Interface::Function.new(
                          params: Interface::Function::Params.empty.with_first_param(
                            Interface::Function::Params::PositionalParams::Required.new(param_type)
                          ),
                          return_type: AST::Types::Union.build(types: return_types),
                          location: nil
                        ),
                        block: nil
                      )
                    end
                  end
                end
              else
                Steep.logger.error "Passing multiple args through Symbol#to_proc is not supported yet"
              end
            end

            type ||= synthesize(node.children[0], hint: hint).type

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

          var_type = if module_context&.class_variables
                       module_context.class_variables[name]&.yield_self {|ty| checker.factory.type(ty) }
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
          name = node.children[0]
          var_type = if module_context&.class_variables
                       module_context.class_variables[name]&.yield_self {|ty| checker.factory.type(ty) }
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
          constr = self

          each_child_node(node) do |child|
            _, constr = constr.synthesize(child)
          end

          add_typing node, type: AST::Builtin.any_type, constr: constr

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
        exn.backtrace.each {|loc| Steep.logger.warn "  #{loc}" }
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

    def type_ivasgn(name, rhs, node)
      rhs_type = synthesize(rhs, hint: type_env.get(ivar: name) { fallback_to_any(node) }).type

      ivar_type = type_env.assign(
        ivar: name,
        type: rhs_type,
        self_type: self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      ) do |error|
        if error
          type = type_env.get(ivar: name)
          typing.add_error(
            Diagnostic::Ruby::IncompatibleAssignment.new(
              node: node,
              lhs_type: type,
              rhs_type: rhs_type,
              result: error
            )
          )
        else
          fallback_to_any node
        end
      end
      add_typing(node, type: ivar_type)
    end

    def masgn_lhs?(lhs)
      lhs.children.all? do |a|
        asgn_type = if a.type == :splat
                      a.children[0]&.type
                    else
                      a.type
                    end
        asgn_type.nil? || asgn_type == :lvasgn || asgn_type == :ivasgn
      end
    end

    def lvasgn(node, type)
      name = node.children[0]
      env = context.lvar_env.assign(name, node: node, type: type) do |declared_type, type, result|
        typing.add_error(
          Diagnostic::Ruby::IncompatibleAssignment.new(
            node: node,
            lhs_type: declared_type,
            rhs_type: type,
            result: result
          )
        )
      end

      add_typing(node, type: type, constr: with_updated_context(lvar_env: env))
    end

    def ivasgn(node, type)
      ivar = node.children[0]

      type_env.assign(
        ivar: ivar,
        type: type,
        self_type: self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type
      ) do |error|
        if error
          var_type = type_env.get(ivar: ivar)
          typing.add_error(
            Diagnostic::Ruby::IncompatibleAssignment.new(
              node: node,
              lhs_type: var_type,
              rhs_type: type,
              result: error
            )
          )
        else
          fallback_to_any node
        end
      end

      add_typing(node, type: type)
    end

    def type_masgn(node)
      lhs, rhs = node.children
      rhs_pair = synthesize(rhs)
      rhs_type = deep_expand_alias(rhs_pair.type)

      constr = rhs_pair.constr

      unless masgn_lhs?(lhs)
        Steep.logger.error("Unsupported masgn lhs node: only lvasgn, ivasgn, and splat are supported")
        _, constr = constr.fallback_to_any(lhs)
        return add_typing(node, type: rhs_type, constr: constr)
      end

      falseys, truthys = partition_flatten_types(rhs_type) do |type|
        type.is_a?(AST::Types::Nil) || (type.is_a?(AST::Types::Literal) && type.value == false)
      end

      unwrap_rhs_type = AST::Types::Union.build(types: truthys)

      case
      when unwrap_rhs_type.is_a?(AST::Types::Tuple) || (rhs.type == :array && rhs.children.none? {|n| n.type == :splat })
        tuple_types = if unwrap_rhs_type.is_a?(AST::Types::Tuple)
                        unwrap_rhs_type.types.dup
                      else
                        rhs.children.map do |node|
                          typing.type_of(node: node)
                        end
                      end

        assignment_nodes = lhs.children.dup
        leading_assignments = []
        trailing_assignments = []

        until assignment_nodes.empty?
          cursor = assignment_nodes.first

          if cursor.type == :splat
            break
          else
            leading_assignments << assignment_nodes.shift
          end
        end

        until assignment_nodes.empty?
          cursor = assignment_nodes.last

          if cursor.type == :splat
            break
          else
            trailing_assignments.unshift assignment_nodes.pop
          end
        end

        leading_assignments.each do |asgn|
          type = tuple_types.first

          if type
            tuple_types.shift
          else
            type = AST::Builtin.nil_type
          end

          case asgn.type
          when :lvasgn
            _, constr = constr.lvasgn(asgn, type)
          when :ivasgn
            _, constr = constr.ivasgn(asgn, type)
          end
        end

        trailing_assignments.reverse_each do |asgn|
          type = tuple_types.last

          if type
            tuple_types.pop
          else
            type = AST::Builtin.nil_type
          end

          case asgn.type
          when :lvasgn
            _, constr = constr.lvasgn(asgn, type)
          when :ivasgn
            _, constr = constr.ivasgn(asgn, type)
          end
        end

        element_type = if tuple_types.empty?
                         AST::Builtin.nil_type
                       else
                         AST::Types::Union.build(types: tuple_types)
                       end
        array_type = AST::Builtin::Array.instance_type(element_type)

        assignment_nodes.each do |asgn|
          case asgn.type
          when :splat
            case asgn.children[0]&.type
            when :lvasgn
              _, constr = constr.lvasgn(asgn.children[0], array_type)
            when :ivasgn
              _, constr = constr.ivasgn(asgn.children[0], array_type)
            end
          when :lvasgn
            _, constr = constr.lvasgn(asgn, element_type)
          when :ivasgn
            _,constr = constr.ivasgn(asgn, element_type)
          end
        end

        unless falseys.empty?
          constr = constr.update_lvar_env {|lvar_env| self.context.lvar_env.join(lvar_env, self.context.lvar_env)}
        end

        add_typing(node, type: rhs_type, constr: constr)

      when flatten_union(unwrap_rhs_type).all? {|type| AST::Builtin::Array.instance_type?(type) }
        array_elements = flatten_union(unwrap_rhs_type).map {|type| type.args[0] }
        element_type = AST::Types::Union.build(types: array_elements + [AST::Builtin.nil_type])

        constr = lhs.children.inject(constr) do |constr, assignment|
          case assignment.type
          when :lvasgn
            _, constr = constr.lvasgn(assignment, element_type)

          when :ivasgn
            _, constr = constr.ivasgn(assignment, element_type)
          when :splat
            case assignment.children[0].type
            when :lvasgn
              _, constr = constr.lvasgn(assignment.children[0], unwrap_rhs_type)
            when :ivasgn
              _, constr = constr.ivasgn(assignment.children[0], unwrap_rhs_type)
            else
              raise
            end
          end

          constr
        end

        unless falseys.empty?
          constr = constr.update_lvar_env {|lvar_env| self.context.lvar_env.join(lvar_env, self.context.lvar_env)}
        end

        add_typing(node, type: rhs_type, constr: constr)
      else
        unless rhs_type.is_a?(AST::Types::Any)
          Steep.logger.error("Unsupported masgn rhs type: array or tuple is supported (#{rhs_type})")
        end
        _, constr = constr.fallback_to_any(lhs)
        add_typing(node, type: rhs_type, constr: constr)
      end
    end

    def optional_proc?(type)
      if type.is_a?(AST::Types::Union)
        if type.types.size == 2
          if type.types.find {|t| t.is_a?(AST::Types::Nil) }
            if proc_type = type.types.find {|t| t.is_a?(AST::Types::Proc) }
              proc_type
            end
          end
        end
      end
    end

    def type_lambda(node, params_node:, body_node:, type_hint:)
      block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)
      params = TypeInference::BlockParams.from_node(params_node, annotations: block_annotations)

      type_hint = deep_expand_alias(type_hint) if type_hint

      case type_hint
      when AST::Types::Proc
        params_hint = type_hint.type.params
        return_hint = type_hint.type.return_type
        block_hint = type_hint.block
      end

      block_constr = for_block(
        block_params: params,
        block_param_hint: params_hint,
        block_type_hint: return_hint,
        block_block_hint: block_hint,
        block_annotations: block_annotations,
        node_type_hint: nil
      )

      block_constr.typing.add_context_for_body(node, context: block_constr.context)

      default_proc_function =
        Interface::Function.new(
          params: Interface::Function::Params.empty,
          return_type: AST::Builtin.any_type,
          location: nil
        )

      params.params.each do |param|
        _, block_constr = block_constr.synthesize(param.node, hint: param.type)
      end

      block =
        if block_param = params.block_param
          if block_param_type = block_param.type
            case block_param_type
            when AST::Types::Proc
              Interface::Block.new(type: block_param_type.type, optional: false)
            else
              if proc_type = optional_proc?(block_param_type)
                Interface::Block.new(type: proc_type.type, optional: true)
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
                  optional: false
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

        if expected_block_type = block_constr.block_context.body_type
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
        block: block
      )

      add_typing node, type: block_type
    end

    def synthesize_children(node, skips: [])
      skips = Set.new.compare_by_identity.merge(skips)

      constr = self

      each_child_node(node) do |child|
        unless skips.include?(child)
          _, constr = constr.synthesize(child)
        end
      end

      constr
    end

    def type_send_interface(node, interface:, receiver:, receiver_type:, method_name:, arguments:, block_params:, block_body:)
      method = interface.methods[method_name]

      if method
        call, constr = type_method_call(node,
                                        method: method,
                                        method_name: method_name,
                                        arguments: arguments,
                                        block_params: block_params,
                                        block_body: block_body,
                                        receiver_type: receiver_type,
                                        topdown_hint: true)

        if call && constr
          case method_name.to_s
          when "[]=", /\w=\Z/
            if typing.has_type?(arguments.last)
              call = call.with_return_type(typing.type_of(node: arguments.last))
            end
          end
        else
          error = Diagnostic::Ruby::UnresolvedOverloading.new(
            node: node,
            receiver_type: receiver_type,
            method_name: method_name,
            method_types: method.method_types
          )
          call = TypeInference::MethodCall::Error.new(
            node: node,
            context: context.method_context,
            method_name: method_name,
            receiver_type: receiver_type,
            errors: [error]
          )

          skips = [receiver]
          skips << node.children[0] if node.type == :block

          constr = synthesize_children(node, skips: skips)
          if block_params
            block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)

            constr.type_block_without_hint(
              node: node,
              block_params: TypeInference::BlockParams.from_node(block_params, annotations: block_annotations),
              block_annotations: block_annotations,
              block_body: block_body
            )
          end
        end

        constr.add_call(call)
      else
        skips = []
        skips << receiver if receiver
        skips << node.children[0] if node.type == :block
        skips << block_params if block_params
        skips << block_body if block_body

        constr = synthesize_children(node, skips: skips)
        if block_params
          block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)

          constr.type_block_without_hint(
            node: node,
            block_params: TypeInference::BlockParams.from_node(block_params, annotations: block_annotations),
            block_annotations: block_annotations,
            block_body: block_body
          )
        end

        constr.add_call(
          TypeInference::MethodCall::NoMethodError.new(
            node: node,
            context: context.method_context,
            method_name: method_name,
            receiver_type: receiver_type,
            error: Diagnostic::Ruby::NoMethod.new(node: node, method: method_name, type: receiver_type)
          )
        )
      end
    end

    def type_send(node, send_node:, block_params:, block_body:, unwrap: false)
      receiver, method_name, *arguments = send_node.children
      recv_type, constr = receiver ? synthesize(receiver) : [AST::Types::Self.new, self]

      if unwrap
        recv_type = unwrap(recv_type)
      end

      receiver_type = checker.factory.deep_expand_alias(recv_type)
      private = receiver.nil? || receiver.type == :self

      type, constr = case receiver_type
                     when nil
                       raise

                     when AST::Types::Any
                       constr = constr.synthesize_children(node, skips: [receiver])
                       constr.add_call(
                         TypeInference::MethodCall::Untyped.new(
                           node: node,
                           context: context.method_context,
                           method_name: method_name
                         )
                       )

                     when AST::Types::Var
                       if upper_bound = variable_context[receiver_type.name]
                         interface = calculate_interface(upper_bound, private: false)

                         constr.type_send_interface(
                           node,
                           interface: interface,
                           receiver: receiver,
                           receiver_type: receiver_type,
                           method_name: method_name,
                           arguments: arguments,
                           block_params: block_params,
                           block_body: block_body
                         )
                       else
                         constr = constr.synthesize_children(node, skips: [receiver])
                         constr.add_call(
                           TypeInference::MethodCall::NoMethodError.new(
                             node: node,
                             context: context.method_context,
                             method_name: method_name,
                             receiver_type: receiver_type,
                             error: Diagnostic::Ruby::NoMethod.new(node: node, method: method_name, type: receiver_type)
                           )
                         )
                       end
                     when AST::Types::Void, AST::Types::Bot, AST::Types::Top, AST::Types::Var
                       constr = constr.synthesize_children(node, skips: [receiver])
                       constr.add_call(
                         TypeInference::MethodCall::NoMethodError.new(
                           node: node,
                           context: context.method_context,
                           method_name: method_name,
                           receiver_type: receiver_type,
                           error: Diagnostic::Ruby::NoMethod.new(node: node, method: method_name, type: receiver_type)
                         )
                       )

                     when AST::Types::Self
                       expanded_self = expand_self(receiver_type)

                       if expanded_self.is_a?(AST::Types::Self)
                         Steep.logger.debug { "`self` type cannot be resolved to concrete type" }

                         constr = constr.synthesize_children(node, skips: [receiver])
                         constr.add_call(
                           TypeInference::MethodCall::NoMethodError.new(
                             node: node,
                             context: context.method_context,
                             method_name: method_name,
                             receiver_type: receiver_type,
                             error: Diagnostic::Ruby::NoMethod.new(node: node, method: method_name, type: receiver_type)
                           )
                         )
                       else
                         interface = calculate_interface(expanded_self,
                                                         private: private,
                                                         self_type: AST::Types::Self.new)

                         constr.type_send_interface(node,
                                                    interface: interface,
                                                    receiver: receiver,
                                                    receiver_type: expanded_self,
                                                    method_name: method_name,
                                                    arguments: arguments,
                                                    block_params: block_params,
                                                    block_body: block_body)
                       end

                     else
                       interface = calculate_interface(receiver_type, private: private, self_type: receiver_type)

                       constr.type_send_interface(node,
                                                  interface: interface,
                                                  receiver: receiver,
                                                  receiver_type: receiver_type,
                                                  method_name: method_name,
                                                  arguments: arguments,
                                                  block_params: block_params,
                                                  block_body: block_body)
                     end

      Pair.new(type: type, constr: constr)
    end

    def calculate_interface(type, private:, self_type: type)
      case type
      when AST::Types::Self
        type = self_type
      when AST::Types::Instance
        type = module_context.instance_type
      when AST::Types::Class
        type = module_context.module_type
      end

      checker.factory.interface(type, private: private, self_type: self_type)
    end

    def expand_self(type)
      if type.is_a?(AST::Types::Self) && self_type
        self_type
      else
        type
      end
    end

    def type_method_call(node, method_name:, receiver_type:, method:, arguments:, block_params:, block_body:, topdown_hint:)
      node_range = node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }

      results = method.method_types.map do |method_type|
        Steep.logger.tagged method_type.to_s do
          typing.new_child(node_range) do |child_typing|
            self.with_new_typing(child_typing).try_method_type(
              node,
              receiver_type: receiver_type,
              method_name: method_name,
              method_type: method_type,
              arguments: arguments,
              block_params: block_params,
              block_body: block_body,
              topdown_hint: topdown_hint
            )
          end
        end
      end

      case
      when results.empty?
        method_type = method.method_types.last
        all_decls = method.method_types.each.with_object(Set[]) do |method_type, set|
          set.merge(method_type.method_decls)
        end

        error = Diagnostic::Ruby::IncompatibleArguments.new(node: node, method_name: method_name, receiver_type: receiver_type, method_types: method.method_types)
        call = TypeInference::MethodCall::Error.new(
          node: node,
          context: context.method_context,
          method_name: method_name,
          receiver_type: receiver_type,
          return_type: method_type.type.return_type,
          errors: [error],
          method_decls: all_decls
        )
        constr = self.with_new_typing(typing.new_child(node_range))
      when (call, constr = results.find {|call, _| call.is_a?(TypeInference::MethodCall::Typed) })
        # Nop
      else
        if results.one?
          call, constr = results[0]
        else
          return
        end
      end
      constr.typing.save!

      [
        call,
        update_lvar_env { constr.context.lvar_env }
      ]
    end

    def inspect
      "#<#{self.class}>"
    end

    def with_child_typing(range:)
      constr = with_new_typing(typing.new_child(range: range))

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

    def try_method_type(node, receiver_type:, method_name:, method_type:, arguments:, block_params:, block_body:, topdown_hint:)
      type_params, instantiation = Interface::TypeParam.rename(method_type.type_params)
      type_param_names = type_params.map(&:name)

      constr = self

      method_type = method_type.instantiate(instantiation)

      variance = Subtyping::VariableVariance.from_method_type(method_type)
      occurence = Subtyping::VariableOccurence.from_method_type(method_type)
      constraints = Subtyping::Constraints.new(unknowns: type_params.map(&:name))
      ccontext = Subtyping::Constraints::Context.new(
        self_type: self_type,
        instance_type: module_context.instance_type,
        class_type: module_context.module_type,
        variance: variance
      )

      upper_bounds = {}

      type_params.each do |param|
        if ub = param.upper_bound
          constraints.add(param.name, super_type: ub, skip: true)
          upper_bounds[param.name] = ub
        end
      end

      checker.push_variable_bounds(upper_bounds) do
        errors = []

        args = TypeInference::SendArgs.new(node: node, arguments: arguments, method_name: method_name, method_type: method_type)
        es = args.each do |arg|
          case arg
          when TypeInference::SendArgs::PositionalArgs::NodeParamPair
            _, constr = constr.type_check_argument(
              arg.node,
              type: arg.param.type,
              receiver_type: receiver_type,
              constraints: constraints,
              errors: errors
            )

          when TypeInference::SendArgs::PositionalArgs::NodeTypePair
            _, constr = bypass_splat(arg.node) do |n|
              constr.type_check_argument(
                n,
                type: arg.node_type,
                receiver_type: receiver_type,
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
            arg_type, _ = constr
                            .with_child_typing(range: arg.node.loc.expression.begin_pos ... arg.node.loc.expression.end_pos)
                            .try_tuple_type!(arg.node.children[0])
            arg.type = arg_type

          when TypeInference::SendArgs::PositionalArgs::MissingArg
            # ignore

          when TypeInference::SendArgs::KeywordArgs::ArgTypePairs
            arg.pairs.each do |node, type|
              _, constr = bypass_splat(node) do |node|
                constr.type_check_argument(
                  node,
                  type: type,
                  receiver_type: receiver_type,
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
            raise arg.inspect
          end

          constr
        end

        errors.push(*es)

        if block_params
          # block is given
          block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)
          block_params_ = TypeInference::BlockParams.from_node(block_params, annotations: block_annotations)

          if method_type.block
            # Method accepts block
            pairs = method_type.block && block_params_&.zip(method_type.block.type.params, nil)

            if pairs
              # Block parameters are compatible with the block type
              block_constr = constr.for_block(
                block_params: block_params_,
                block_param_hint: method_type.block.type.params,
                block_type_hint: method_type.block.type.return_type,
                block_block_hint: nil,
                block_annotations: block_annotations,
                node_type_hint: method_type.type.return_type
              )
              block_constr = block_constr.with_new_typing(
                block_constr.typing.new_child(
                  range: block_constr.typing.block_range(node)
                )
              )

              block_constr.typing.add_context_for_body(node, context: block_constr.context)

              pairs.each do |param, type|
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
              end

              method_type, solved, s = apply_solution(errors, node: node, method_type: method_type) {
                constraints.solution(
                  checker,
                  variables: method_type.type.params.free_variables + method_type.block.type.params.free_variables,
                  context: ccontext
                )
              }

              if solved
                # Ready for type check the body of the block
                block_constr = block_constr.update_lvar_env {|env| env.subst(s) }
                if block_body
                  block_body_type = block_constr.synthesize_block(
                    node: node,
                    block_body: block_body,
                    block_type_hint: method_type.block.type.return_type
                  )
                else
                  block_body_type = AST::Builtin.nil_type
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
            # Block is given but method doesn't accept
            #
            constr.type_block_without_hint(node: node, block_annotations: block_annotations, block_params: block_params_, block_body: block_body) do |error|
              errors << error
            end

            errors << Diagnostic::Ruby::UnexpectedBlockGiven.new(
              node: node,
              method_type: method_type
            )

            method_type = eliminate_vars(method_type, type_param_names)
            return_type = method_type.type.return_type
          end
        else
          # Block syntax is not given
          arg = args.block_pass_arg

          case
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
            # Unexpected block is given
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

        call = if errors.empty?
                 TypeInference::MethodCall::Typed.new(
                   node: node,
                   context: context.method_context,
                   receiver_type: receiver_type,
                   method_name: method_name,
                   actual_method_type: method_type,
                   return_type: return_type || method_type.type.return_type,
                   method_decls: method_type.method_decls
                 )
               else
                 TypeInference::MethodCall::Error.new(
                   node: node,
                   context: context.method_context,
                   receiver_type: receiver_type,
                   method_name: method_name,
                   return_type: return_type || method_type.type.return_type,
                   method_decls: method_type.method_decls,
                   errors: errors
                 )
               end

        [
          call,
          constr
        ]
      end
    end

    def type_check_argument(node, receiver_type:, type:, constraints:, report_node: node, errors:)
      check(node, type, constraints: constraints) do |expected, actual, result|
        errors << Diagnostic::Ruby::ArgumentTypeMismatch.new(
            node: report_node,
            receiver_type: receiver_type,
            expected: expected,
            actual: actual,
            result: result
          )
      end
    end

    def type_block_without_hint(node:, block_annotations:, block_params:, block_body:, &block)
      unless block_params
        typing.add_error(
          Diagnostic::Ruby::UnsupportedSyntax.new(
            node: node.children[1],
            message: "Unsupported block params pattern, probably masgn?"
          )
        )
        block_params = TypeInference::BlockParams.new(leading_params: [], optional_params: [], rest_param: nil, trailing_params: [], block_param: nil)
      end

      block_constr = for_block(
        block_params: block_params,
        block_param_hint: nil,
        block_type_hint: AST::Builtin.any_type,
        block_block_hint: nil,
        block_annotations: block_annotations,
        node_type_hint: AST::Builtin.any_type
      )

      block_constr.typing.add_context_for_body(node, context: block_constr.context)

      block_params.params.each do |param|
        _, block_constr = block_constr.synthesize(param.node, hint: param.type)
      end

      block_type = block_constr.synthesize_block(node: node, block_type_hint: nil, block_body: block_body)

      if expected_block_type = block_constr.block_context.body_type
        block_constr.check_relation(sub_type: block_type, super_type: expected_block_type).else do |result|
          block_constr.typing.add_error(
            Diagnostic::Ruby::BlockBodyTypeMismatch.new(
              node: node,
              expected: expected_block_type,
              actual: block_type,
              result: result
            )
          )
        end
      end
    end

    def for_block(block_params:, block_param_hint:, block_type_hint:, block_block_hint:, block_annotations:, node_type_hint:)
      block_param_pairs = block_param_hint && block_params.zip(block_param_hint, block_block_hint)

      param_types_hash = {}
      if block_param_pairs
        block_param_pairs.each do |param, type|
          var_name = param.var
          param_types_hash[var_name] = type
        end
      else
        block_params.each do |param|
          var_name = param.var
          param_types_hash[var_name] = param.type || AST::Builtin.any_type
        end
      end

      decls = param_types_hash.each.with_object({}) do |(name, type), hash|
        hash[name] = TypeInference::LocalVariableTypeEnv::Entry.new(type: type)
      end
      lvar_env = context.lvar_env
                   .pin_assignments
                   .except(decls.keys)
                   .update(assigned_types: decls)
                   .annotate(block_annotations)

      break_type = if block_annotations.break_type
                     union_type(node_type_hint, block_annotations.break_type)
                   else
                     node_type_hint
                   end

      block_context = TypeInference::Context::BlockContext.new(
        body_type: block_annotations.block_type || block_type_hint || AST::Builtin.any_type
      )
      break_context = TypeInference::Context::BreakContext.new(
        break_type: break_type,
        next_type: block_context.body_type
      )

      self_type = self.self_type
      module_context = self.module_context

      if implements = block_annotations.implement_module_annotation
        module_context = default_module_context(
          implements.name,
          const_env: self.module_context.const_env,
          current_namespace: current_namespace
        )

        self_type = module_context.module_type
      end

      if annotation_self_type = block_annotations.self_type
        self_type = annotation_self_type
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
          type_env: type_env.dup,
          lvar_env: lvar_env,
          call_context: self.context.call_context,
          variable_context: variable_context
        )
      )
    end

    def synthesize_block(node:, block_type_hint:, block_body:)
      if block_body
        body_type, _, context = synthesize(block_body, hint: block_context.body_type || block_type_hint)

        range = block_body.loc.expression.end_pos..node.loc.end.begin_pos
        typing.add_context(range, context: context)

        body_type
      else
        AST::Builtin.nil_type
      end
    end

    def each_child_node(node)
      if block_given?
        node.children.each do |child|
          if child.is_a?(::AST::Node)
            yield child
          end
        end
      else
        enum_for :each_child_node, node
      end
    end

    def current_namespace
      module_context&.current_namespace || AST::Namespace.root
    end

    def nested_namespace_for_module(module_name)
      if module_name.namespace.relative?
        (current_namespace + module_name.namespace).append(module_name.name)
      else
        module_name.to_namespace
      end
    end

    def absolute_name(module_name)
      if current_namespace
        module_name.with_prefix(current_namespace)
      else
        module_name.absolute!
      end
    end

    def absolute_type(type)
      if type
        checker.builder.absolute_type(type, current: current_namespace)
      end
    end

    def union_type(*types)
      raise if types.empty?
      AST::Types::Union.build(types: types)
    end

    def validate_method_definitions(node, module_name)
      module_name_1 = module_name.name
      member_decl_count = checker.factory.env.class_decls[module_name_1].decls.count {|d| d.decl.each_member.count > 0 }

      return unless member_decl_count == 1

      expected_instance_method_names = (module_context.instance_definition&.methods || {}).each.with_object(Set[]) do |(name, method), set|
        if method.implemented_in == module_context.instance_definition.type_name
          set << name
        end
      end
      expected_module_method_names = (module_context.module_definition&.methods || {}).each.with_object(Set[]) do |(name, method), set|
        if name != :new
          if method.implemented_in == module_context.module_definition.type_name
            set << name
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

    def self_class?(node)
      node.type == :send && node.children[0]&.type == :self && node.children[1] == :class
    end

    def namespace_module?(node)
      nodes = case node.type
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

    def type_any_rec(node)
      add_typing node, type: AST::Builtin.any_type

      each_child_node(node) do |child|
        type_any_rec(child)
      end

      Pair.new(type: AST::Builtin.any_type, constr: self)
    end

    def unwrap(type)
      expand_alias(type) do |expanded|
        case
        when expanded.is_a?(AST::Types::Union)
          types = expanded.types.reject {|type| type.is_a?(AST::Types::Nil)}
          AST::Types::Union.build(types: types)
        else
          type
        end
      end
    end

    def deep_expand_alias(type, &block)
      checker.factory.deep_expand_alias(type, &block)
    end

    def flatten_union(type)
      checker.factory.flatten_union(type)
    end

    def select_flatten_types(type, &block)
      types = flatten_union(deep_expand_alias(type))
      types.select(&block)
    end

    def partition_flatten_types(type, &block)
      types = flatten_union(deep_expand_alias(type))
      types.partition(&block)
    end

    def flatten_array_elements(type)
      flatten_union(deep_expand_alias(type)).flat_map do |type|
        if AST::Builtin::Array.instance_type?(type)
          type.args
        else
          [type]
        end
      end
    end

    def expand_alias(type, &block)
      checker.factory.expand_alias(type, &block)
    end

    def test_literal_type(literal, hint)
      if hint
        case hint
        when AST::Types::Any
          nil
        else
          literal_type = AST::Types::Literal.new(value: literal, location: nil)
          if check_relation(sub_type: literal_type, super_type: hint).success?
            hint
          end
        end
      end
    end

    def to_instance_type(type, args: nil)
      args = args || case type
                     when AST::Types::Name::Singleton
                       checker.factory.env.class_decls[type.name].type_params.each.map { AST::Builtin.any_type }
                     else
                       raise "unexpected type to to_instance_type: #{type}"
                     end

      AST::Types::Name::Instance.new(name: type.name, args: args)
    end

    def try_tuple_type!(node, hint: nil)
      if node.type == :array && (hint.nil? || hint.is_a?(AST::Types::Tuple))
        node_range = node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }

        typing.new_child(node_range) do |child_typing|
          if pair = with_new_typing(child_typing).try_tuple_type(node, hint)
            return pair.with(constr: pair.constr.save_typing)
          end
        end
      end

      synthesize(node, hint: hint)
    end

    def try_tuple_type(node, hint)
      if hint
        if node.children.size != hint.types.size
          return
        end
      end

      constr = self
      element_types = []

      each_child_node(node).with_index do |child, index|
        child_hint = if hint
                       hint.types[index]
                     end
        type, constr = constr.synthesize(child, hint: child_hint)
        element_types << type
      end

      constr.add_typing(node, type: AST::Types::Tuple.new(types: element_types))
    end

    def try_array_type(node, hint)
      element_hint = hint ? hint.args[0] : nil

      constr = self
      element_types = []

      each_child_node(node) do |child|
        case child.type
        when :splat
          type, constr = constr.synthesize(child.children[0], hint: hint)
          if AST::Builtin::Array.instance_type?(type)
            element_types << type.args[0]
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

    # Try to give record type to hash_node.
    #
    # Returns nil when it cannot have a record type.
    # `record_type` can be nil when the keys are not specified.
    #
    def type_hash_record(hash_node, record_type)
      raise unless hash_node.type == :hash || hash_node.type == :kwargs

      constr = self

      if record_type
        elements = record_type.elements.dup
      else
        elements = {}
      end

      elems = {}

      each_child_node(hash_node) do |child|
        if child.type == :pair
          case child.children[0].type
          when :sym, :str, :int
            key_node = child.children[0]
            value_node = child.children[1]

            key = key_node.children[0]

            _, constr = constr.synthesize(key_node, hint: AST::Types::Literal.new(value: key))
            value_type, constr = constr.synthesize(value_node, hint: elements[key])

            elems[key] = value_type
          else
            return
          end
        else
          return
        end
      end

      type = AST::Types::Record.new(elements: elems)
      constr.add_typing(hash_node, type: type)
    end

    # Give hash_node a type based on hint.
    #
    # * When hint is Record type, it may have record type.
    # * When hint is union type, it tries recursively with the union cases.
    # * Otherwise, it tries to be a hash instance.
    #
    def type_hash(hash_node, hint:)
      hint = deep_expand_alias(hint)
      range = hash_node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }

      case hint
      when AST::Types::Record
        with_child_typing(range: range) do |constr|
          pair = constr.type_hash_record(hash_node, hint)
          if pair
            return pair.with(constr: pair.constr.save_typing)
          end
        end
      when AST::Types::Union
        pair = pick_one_of(hint.types, range: range) do |type, constr|
          constr.type_hash(hash_node, hint: type)
        end

        if pair
          return pair
        end
      end

      key_types = []
      value_types = []

      if AST::Builtin::Hash.instance_type?(hint)
        key_hint, value_hint = hint.args
      end

      hint_hash = AST::Builtin::Hash.instance_type(
        key_hint || AST::Builtin.any_type,
        value_hint || AST::Builtin.any_type
      )

      constr = self

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
              pair = constr.synthesize(elem_, hint: hint_hash)

              if AST::Builtin::Hash.instance_type?(pair.type)
                key_types << pair.type.args[0]
                value_types << pair.type.args[1]
              end

              pair
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

    def pick_one_of(types, range:)
      types.each do |type|
        with_child_typing(range: range) do |constr|
          type_, constr = yield type, constr

          constr.check_relation(sub_type: type_, super_type: type).then do
            constr = constr.save_typing
            return Pair.new(type: type, constr: constr)
          end
        end
      end

      nil
    end

    def save_typing
      typing.save!
      with_new_typing(typing.parent)
    end
  end
end
