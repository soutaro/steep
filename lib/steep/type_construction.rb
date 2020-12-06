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
        self.class.new(
          type: type,
          constr: constr
        )
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
      Steep.logger.debug { "check_relation: self:#{self_type} |- #{sub_type} <: #{super_type}" }
      checker.check(Subtyping::Relation.new(sub_type: sub_type, super_type: super_type), self_type: self_type, constraints: constraints)
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

      if annots&.return_type && method_type&.return_type
        check_relation(sub_type: annots.return_type, super_type: method_type.return_type).else do |result|
          typing.add_error Errors::MethodReturnTypeAnnotationMismatch.new(node: node,
                                                                          method_type: method_type.return_type,
                                                                          annotation_type: annots.return_type,
                                                                          result: result)
        end
      end

      # constructor_method = method&.attributes&.include?(:constructor)

      if method_type
        var_types = TypeConstruction.parameter_types(args, method_type)
        unless TypeConstruction.valid_parameter_env?(var_types, args.reject {|arg| arg.type == :blockarg}, method_type.params)
          typing.add_error Errors::MethodArityMismatch.new(node: node)
        end
      end

      if (block_arg = args.find {|arg| arg.type == :blockarg})
        if method_type&.block
          block_type = if method_type.block.optional?
                         AST::Types::Union.build(types: [method_type.block.type, AST::Builtin.nil_type])
                       else
                         method_type.block.type
                       end
          var_types[block_arg.children[0]] = block_type
        end
      end

      super_method = if definition
                       if (this_method = definition.methods[method_name])
                         if module_context&.class_name == this_method.defined_in
                           this_method.super_method
                         else
                           this_method
                         end
                       end
                     end

      method_context = TypeInference::Context::MethodContext.new(
        name: method_name,
        method: definition && definition.methods[method_name],
        method_type: method_type,
        return_type: annots.return_type || method_type&.return_type || AST::Builtin.any_type,
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
        self_type: annots.self_type || self_type
      )

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: annots.self_type || self_type
      )

      if var_types
        lvar_env = lvar_env.update(
          assigned_types: var_types.each.with_object({}) {|(var, type), hash|
            arg_node = args.find {|arg| arg.children[0] == var }
            hash[var.name] = TypeInference::LocalVariableTypeEnv::Entry.new(type: type, nodes: [arg_node].compact)
          }
        )
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
          call_context: call_context
        ),
        typing: typing,
      )
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

    def for_module(node)
      new_module_name = module_name_from_node(node.children.first) or raise "Unexpected module name: #{node.children.first}"
      new_namespace = nested_namespace_for_module(new_module_name)

      const_context = [new_namespace] + self.module_context.const_env.context
      module_const_env = TypeInference::ConstantEnv.new(factory: checker.factory, context: const_context)

      annots = source.annotations(block: node, factory: checker.factory, current_module: new_namespace)
      module_type = AST::Builtin::Module.instance_type

      implement_module_name = implement_module(module_name: new_module_name, annotations: annots)

      if implement_module_name
        module_name = implement_module_name.name
        module_args = implement_module_name.args.map {|x| AST::Types::Var.new(name: x)}

        type_name_ = implement_module_name.name
        module_entry = checker.factory.definition_builder.env.class_decls[type_name_]
        instance_def = checker.factory.definition_builder.build_instance(type_name_)
        module_def = checker.factory.definition_builder.build_singleton(type_name_)

        instance_type = AST::Types::Intersection.build(
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
            AST::Types::Name::Instance.new(name: module_name, args: module_args)
          ].compact
        )

        module_type = AST::Types::Name::Singleton.new(name: module_name)
      end

      if annots.instance_type
        instance_type = annots.instance_type
      end

      if annots.module_type
        module_type = annots.module_type
      end

      module_context_ = TypeInference::Context::ModuleContext.new(
        instance_type: instance_type,
        module_type: annots.self_type || module_type,
        implement_name: implement_module_name,
        current_namespace: new_namespace,
        const_env: module_const_env,
        class_name: absolute_name(new_module_name),
        instance_definition: instance_def,
        module_definition: module_def
      )

      module_type_env = TypeInference::TypeEnv.build(annotations: annots,
                                                     subtyping: checker,
                                                     const_env: module_const_env,
                                                     signatures: checker.factory.env)

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: module_context_.module_type
      ).annotate(annots)

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        typing: typing,
        context: TypeInference::Context.new(
          method_context: nil,
          block_context: nil,
          break_context: nil,
          module_context: module_context_,
          self_type: module_context_.module_type,
          type_env: module_type_env,
          lvar_env: lvar_env,
          call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context_.class_name)
        )
      )
    end

    def for_class(node)
      new_class_name = module_name_from_node(node.children.first) or raise "Unexpected class name: #{node.children.first}"
      super_class_name = node.children[1] && module_name_from_node(node.children[1])
      new_namespace = nested_namespace_for_module(new_class_name)

      annots = source.annotations(block: node, factory: checker.factory, current_module: new_namespace)

      implement_module_name = implement_module(module_name: new_class_name, super_name: super_class_name, annotations: annots)

      if annots.implement_module_annotation
        new_class_name = implement_module_name.name
      end

      if implement_module_name
        class_name = implement_module_name.name
        class_args = implement_module_name.args.map {|x| AST::Types::Var.new(name: x)}

        type_name_ = implement_module_name.name
        instance_def = checker.factory.definition_builder.build_instance(type_name_)
        module_def = checker.factory.definition_builder.build_singleton(type_name_)

        instance_type = AST::Types::Name::Instance.new(name: class_name, args: class_args)
        module_type = AST::Types::Name::Singleton.new(name: class_name)
      end

      if annots.instance_type
        instance_type = annots.instance_type
      end

      if annots.module_type
        module_type = annots.module_type
      end

      const_context = [new_namespace] + self.module_context.const_env.context
      class_const_env = TypeInference::ConstantEnv.new(factory: checker.factory, context: const_context)

      module_context = TypeInference::Context::ModuleContext.new(
        instance_type: annots.instance_type || instance_type,
        module_type: annots.self_type || annots.module_type || module_type,
        implement_name: implement_module_name,
        current_namespace: new_namespace,
        const_env: class_const_env,
        class_name: absolute_name(new_class_name),
        module_definition: module_def,
        instance_definition: instance_def
      )

      class_type_env = TypeInference::TypeEnv.build(annotations: annots,
                                                    subtyping: checker,
                                                    const_env: class_const_env,
                                                    signatures: checker.factory.env)

      lvar_env = TypeInference::LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: module_context.module_type
      ).annotate(annots)

      class_body_context = TypeInference::Context.new(
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: module_context.module_type,
        type_env: class_type_env,
        lvar_env: lvar_env,
        call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context.class_name)
      )

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        typing: typing,
        context: class_body_context
      )
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
        self_type: module_context.module_type
      ).annotate(annots)

      body_context = TypeInference::Context.new(
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: module_context.module_type,
        type_env: type_env,
        lvar_env: lvar_env,
        call_context: TypeInference::MethodCall::ModuleContext.new(type_name: module_context.class_name)
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
              Errors::IncompatibleTypeCase.new(
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
          Errors::IncompatibleAnnotation.new(node: node,
                                             var_name: var,
                                             relation: relation,
                                             result: result)
        )
      end

      type_env = context.type_env

      if type_case_override
        type_env = type_env.with_annotations(self_type: self_type)
      end

      type_env = type_env.with_annotations(
        ivar_types: annots.ivar_types,
        const_types: annots.const_types,
        gvar_types: {},
        self_type: self_type
      ) do |var, relation, result|
        typing.add_error(
          Errors::IncompatibleAnnotation.new(node: node,
                                             var_name: var,
                                             relation: relation,
                                             result: result)
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

    def synthesize(node, hint: nil)
      Steep.logger.tagged "synthesize:(#{node.location.expression.to_s.split(/:/, 2).last})" do
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
            name = var.name

            case name
            when :_, :__any__
              synthesize(rhs, hint: AST::Builtin.any_type).yield_self do |pair|
                add_typing(node, type: AST::Builtin.any_type, constr: pair.constr)
              end
            when :__skip__
              add_typing(node, type: AST::Builtin.any_type)
            else
              if !hint || hint.is_a?(AST::Types::Void)
                hint = context.lvar_env.declared_types[name]&.type
              end

              rhs_result = synthesize(rhs, hint: hint)

              constr = rhs_result.constr.update_lvar_env do |lvar_env|
                lvar_env.assign(name, node: node, type: rhs_result.type) do |declared_type, actual_type, result|
                  typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                      lhs_type: declared_type,
                                                                      rhs_type: actual_type,
                                                                      result: result))
                end
              end

              add_typing(node, type: rhs_result.type, constr: constr)
            end
          end

        when :lvar
          yield_self do
            var = node.children[0]
            if (type = context.lvar_env[var.name])
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
                args = TypeInference::SendArgs.from_nodes(node.children.dup)

                call, constr = type_method_call(node,
                                                receiver_type: self_type,
                                                method_name: method_context.name,
                                                method: super_method,
                                                args: args,
                                                block_params: nil,
                                                block_body: nil,
                                                topdown_hint: true)

                constr.add_call(call)
              else
                fallback_to_any node do
                  Errors::UnexpectedSuper.new(node: node, method: method_context.name)
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
              type_lambda(node, block_params: params, block_body: body, type_hint: hint)
            else
              type_send(node, send_node: send_node, block_params: params, block_body: body, unwrap: send_node.type == :csend)
            end
          end

        when :def
          yield_self do
            name, args_node, body_node = node.children

            new = for_new_method(name,
                                 node,
                                 args: args_node.children,
                                 self_type: module_context&.instance_type,
                                 definition: module_context&.instance_definition)
            new.typing.add_context_for_node(node, context: new.context)
            new.typing.add_context_for_body(node, context: new.context)

            each_child_node(args_node) do |arg|
              _, new = new.synthesize(arg)
            end

            body_pair = if body_node
                          return_type = expand_alias(new.method_context&.return_type)
                          if return_type && !return_type.is_a?(AST::Types::Void)
                            new.check(body_node, return_type) do |_, actual_type, result|
                              typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                                  expected: new.method_context&.return_type,
                                                                                  actual: actual_type,
                                                                                  result: result))
                            end
                          else
                            new.synthesize(body_node)
                          end
                        else
                          return_type = expand_alias(new.method_context&.return_type)
                          if return_type && !return_type.is_a?(AST::Types::Void)
                            result = check_relation(sub_type: AST::Builtin.nil_type, super_type: return_type)
                            if result.failure?
                              typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                                  expected: new.method_context&.return_type,
                                                                                  actual: AST::Builtin.nil_type,
                                                                                  result: result))
                            end
                          end

                          Pair.new(type: AST::Builtin.nil_type, constr: new)
                        end

            if body_node
              begin_pos = body_node.loc.expression.end_pos
              end_pos = node.loc.end.begin_pos

              typing.add_context(begin_pos..end_pos, context: body_pair.context)
            end

            if module_context
              module_context.defined_instance_methods << node.children[0]
            end

            add_typing(node, type: AST::Builtin::Symbol.instance_type)
          end

        when :defs
          synthesize(node.children[0]).type.tap do |self_type|
            self_type = expand_self(self_type)
            definition = case self_type
                         when AST::Types::Name::Instance
                           name = self_type.name
                           checker.factory.definition_builder.build_singleton(name)
                         when AST::Types::Name::Singleton
                           name = self_type.name
                           checker.factory.definition_builder.build_singleton(name)
                         end

            new = for_new_method(node.children[1],
                                 node,
                                 args: node.children[2].children,
                                 self_type: self_type,
                                 definition: definition)
            new.typing.add_context_for_node(node, context: new.context)
            new.typing.add_context_for_body(node, context: new.context)

            each_child_node(node.children[2]) do |arg|
              new.synthesize(arg)
            end

            if node.children[3]
              return_type = expand_alias(new.method_context&.return_type)
              if return_type && !return_type.is_a?(AST::Types::Void)
                new.check(node.children[3], return_type) do |return_type, actual_type, result|
                  typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                      expected: return_type,
                                                                      actual: actual_type,
                                                                      result: result))
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
            if node.children.size > 0
              method_return_type = expand_alias(method_context&.return_type)

              return_types = node.children.map do |value|
                synthesize(value,
                           hint: if method_return_type.is_a?(AST::Types::Void)
                                   nil
                                 else
                                   method_return_type
                                 end).type
              end

              value_type = if return_types.size == 1
                             return_types.first
                           else
                             AST::Builtin::Array.instance_type(union_type(*return_types))
                           end

              if method_return_type
                unless method_return_type.is_a?(AST::Types::Void)
                  result = check_relation(sub_type: value_type, super_type: method_return_type)

                  if result.failure?
                    typing.add_error(Errors::ReturnTypeMismatch.new(node: node,
                                                                    expected: method_context&.return_type,
                                                                    actual: value_type,
                                                                    result: result))
                  end
                end
              end
            end

            add_typing(node, type: AST::Builtin.bottom_type)
          end

        when :break
          value = node.children[0]

          if break_context
            case
            when value && break_context.break_type
              check(value, break_context.break_type) do |break_type, actual_type, result|
                typing.add_error Errors::BreakTypeMismatch.new(node: node,
                                                               expected: break_type,
                                                               actual: actual_type,
                                                               result: result)
              end
            when !value
              # ok
            else
              synthesize(value) if value
              typing.add_error Errors::UnexpectedJumpValue.new(node: node)
            end
          else
            synthesize(value)
            typing.add_error Errors::UnexpectedJump.new(node: node)
          end

          add_typing(node, type: AST::Builtin.bottom_type)

        when :next
          value = node.children[0]

          if break_context
            case
            when value && break_context.next_type
              check(value, break_context.next_type) do |break_type, actual_type, result|
                typing.add_error Errors::BreakTypeMismatch.new(node: node,
                                                               expected: break_type,
                                                               actual: actual_type,
                                                               result: result)
              end
            when !value
              # ok
            else
              synthesize(value) if value
              typing.add_error Errors::UnexpectedJumpValue.new(node: node)
            end
          else
            synthesize(value)
            typing.add_error Errors::UnexpectedJump.new(node: node)
          end

          add_typing(node, type: AST::Builtin.bottom_type)

        when :retry
          unless break_context
            typing.add_error Errors::UnexpectedJump.new(node: node)
          end
          add_typing(node, type: AST::Builtin.bottom_type)

        when :arg, :kwarg, :procarg0
          yield_self do
            var = node.children[0]
            type = context.lvar_env[var.name]

            if type
              add_typing(node, type: type)
            else
              type = AST::Builtin.any_type
              if context&.method_context&.method_type
                Steep.logger.error { "Unknown arg type: #{node}" }
              end

              lvasgn(node, type)
            end
          end

        when :optarg, :kwoptarg
          yield_self do
            var = node.children[0]
            rhs = node.children[1]

            var_type = context.lvar_env[var.name]
            node_type, constr = synthesize(rhs, hint: var_type)

            type = AST::Types::Union.build(types: [var_type, node_type])

            constr_ = constr.update_lvar_env do |env|
              env.assign(var.name, node: node, type: type) do |declared_type, type, result|
                typing.add_error(
                  Errors::IncompatibleAssignment.new(node: node,
                                                     lhs_type: declared_type,
                                                     rhs_type: type,
                                                     result: result)
                )
              end
            end

            add_typing(node, type: type, constr: constr_)
          end

        when :restarg
          yield_self do
            var = node.children[0]
            type = context.lvar_env[var.name]
            unless type
              if context&.method_context&.method_type
                Steep.logger.error { "Unknown variable: #{node}" }
              end
              typing.add_error Errors::FallbackAny.new(node: node)
              type = AST::Builtin::Array.instance_type(AST::Builtin.any_type)
            end

            add_typing(node, type: type)
          end

        when :kwrestarg
          yield_self do
            var = node.children[0]
            type = context.lvar_env[var.name]
            unless type
              if context&.method_context&.method_type
                Steep.logger.error { "Unknown variable: #{node}" }
              end
              typing.add_error Errors::FallbackAny.new(node: node)
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

        when :hash
          yield_self do
            ty = try_hash_type(node, hint) and return ty

            if AST::Builtin::Hash.instance_type?(hint)
              key_hint = hint.args[0]
              value_hint = hint.args[1]
            end

            key_types = []
            value_types = []

            each_child_node(node) do |child|
              case child.type
              when :pair
                key, value = child.children
                key_types << synthesize(key, hint: key_hint).type.yield_self do |type|
                  select_super_type(type, key_hint)
                end
                value_types << synthesize(value, hint: value_hint).type.yield_self do |type|
                  select_super_type(type, value_hint)
                end
              when :kwsplat
                expand_alias(synthesize(child.children[0]).type) do |splat_type, original_type|
                  if AST::Builtin::Hash.instance_type?(splat_type)
                    key_types << splat_type.args[0]
                    value_types << splat_type.args[1]
                  else
                    typing.add_error Errors::UnexpectedSplat.new(node: child, type: original_type)
                    key_types << AST::Builtin.any_type
                    value_types << AST::Builtin.any_type
                  end
                end
              else
                raise "Unexpected non pair: #{child.inspect}" unless child.type == :pair
              end
            end

            key_type = key_types.empty? ? AST::Builtin.any_type : AST::Types::Union.build(types: key_types)
            value_type = value_types.empty? ? AST::Builtin.any_type : AST::Types::Union.build(types: value_types)

            if key_types.empty? && value_types.empty? && !hint
              typing.add_error Errors::FallbackAny.new(node: node)
            end

            add_typing(node, type: AST::Builtin::Hash.instance_type(key_type, value_type))
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
            _, constr = constr.synthesize(name)
            _, constr = constr.synthesize(sup) if sup

            constr.for_class(node).tap do |constructor|
              constructor.typing.add_context_for_node(node, context: constructor.context)
              constructor.typing.add_context_for_body(node, context: constructor.context)

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
            _, constr = constr.synthesize(name)

            for_module(node).yield_self do |constructor|
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
            constructor = constr.for_sclass(node, type)

            unless constructor
              typing.add_error(
                Errors::UnsupportedSyntax.new(
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
              const_type = type_env.get(const: const_name) {}
              value_type, constr = constr.synthesize(node.children.last, hint: const_type)
              type = type_env.assign(const: const_name, type: value_type, self_type: self_type) do |error|
                case error
                when Subtyping::Result::Failure
                  const_type = type_env.get(const: const_name)
                  typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                      lhs_type: const_type,
                                                                      rhs_type: value_type,
                                                                      result: error))
                when nil
                  typing.add_error(Errors::UnknownConstantAssigned.new(node: node, type: value_type))
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
                    typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                        lhs_type: type,
                                                                        rhs_type: rhs_type,
                                                                        result: result))
                  end
                end
              end

              add_typing(node, type: block_type.type.return_type)
            else
              typing.add_error(Errors::UnexpectedYield.new(node: node))
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
                  checker.factory.method_type(method_type, self_type: self_type, method_decls: Set[]).return_type
                }
                add_typing(node, type: union_type(*types))
              else
                typing.add_error(Errors::UnexpectedSuper.new(node: node, method: method_context.name))
                fallback_to_any node
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
                typing.add_error Errors::FallbackAny.new(node: node)
                add_typing node, type: AST::Builtin::Array.instance_type(AST::Builtin.any_type)
              end
            else
              node_range = node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }

              if hint && !(tuples = select_flatten_types(hint) {|type| type.is_a?(AST::Types::Tuple) }).empty?
                tuples.each do |tuple|
                  typing.new_child(node_range) do |child_typing|
                    pair = with_new_typing(child_typing).try_tuple_type(node, tuple)
                    if pair && pair.constr.check_relation(sub_type: pair.type, super_type: hint).success?
                      child_typing.save!
                      return pair.with(constr: pair.constr.with_new_typing(typing))
                    end
                  end
                end
              end

              if hint && !(arrays = select_flatten_types(hint) {|type| AST::Builtin::Array.instance_type?(type) }).empty?
                arrays.each do |array|
                  typing.new_child(node_range) do |child_typing|
                    pair = with_new_typing(child_typing).try_array_type(node, array)
                    if pair.constr.check_relation(sub_type: pair.type, super_type: hint).success?
                      child_typing.save!
                      return pair.with(constr: pair.constr.with_new_typing(typing))
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

            left_type, constr = synthesize(left)

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing)
            truthy_env, falsey_env = interpreter.eval(env: constr.context.lvar_env, type: left_type, node: left)

            right_type, constr = constr
                                   .update_lvar_env { truthy_env }
                                   .tap {|constr| typing.add_context_for_node(right, context: constr.context) }
                                   .for_branch(right)
                                   .synthesize(right)

            truthy_env, _ = interpreter.eval(env: truthy_env, type: right_type, node: right)

            env = if right_type.is_a?(AST::Types::Bot)
                    falsey_env
                  else
                    context.lvar_env.join(falsey_env, constr.context.lvar_env)
                  end

            type = case
                   when left_type.is_a?(AST::Types::Logic::Base) && right_type.is_a?(AST::Types::Logic::Base)
                     AST::Types::Logic::Env.new(truthy: truthy_env, falsy: env)
                   when check_relation(sub_type: left_type, super_type: AST::Types::Boolean.new).success?
                     union_type(left_type, right_type)
                   else
                     union_type(right_type, AST::Builtin.nil_type)
                   end

            add_typing(node,
                       type: type,
                       constr: constr.update_lvar_env { env })
          end

        when :or
          yield_self do
            left, right = node.children

            left_type, constr = synthesize(left, hint: hint)

            interpreter = TypeInference::LogicTypeInterpreter.new(subtyping: checker, typing: typing)
            truthy_env, falsey_env = interpreter.eval(env: constr.context.lvar_env, type: left_type, node: left)

            left_type, _ = checker.factory.unwrap_optional(left_type)
            right_type, constr = constr
                                   .update_lvar_env { falsey_env }
                                   .tap {|constr| typing.add_context_for_node(right, context: constr.context) }
                                   .for_branch(right)
                                   .synthesize(right, hint: left_type)

            _, falsey_env = interpreter.eval(env: falsey_env, type: right_type, node: right)

            env = if right_type.is_a?(AST::Types::Bot)
                    truthy_env
                  else
                    context.lvar_env.join(truthy_env, constr.context.lvar_env)
                  end

            type = case
                   when left_type.is_a?(AST::Types::Logic::Base) && right_type.is_a?(AST::Types::Logic::Base)
                     AST::Types::Logic::Env.new(truthy: env, falsy: falsey_env)
                   else
                     union_type(left_type, right_type)
                   end

            add_typing(node,
                       type: type,
                       constr: constr.update_lvar_env { env })
          end

        when :if
          cond, true_clause, false_clause = node.children

          cond_type, constr = synthesize(cond)
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
                var_node = cond.updated(
                  :lvar,
                  [
                    ASTUtils::Labeling::LabeledName.new(name: first_var, label: 0)
                  ]
                )
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
                  test_type, test_constr = test_constr.synthesize(test_node)
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
                  typing.add_error Errors::ElseOnExhaustiveCase.new(node: els, type: cond_type)
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

              whens.each do |clause|
                *tests, body = clause.children

                test_constr = when_constr
                test_envs = []

                tests.each do |test|
                  test_type, test_constr = test_constr.synthesize(test)
                  truthy_env, falsy_env = interpreter.eval(env: test_constr.context.lvar_env, type: test_type, node: test)
                  test_envs << truthy_env
                  test_constr = test_constr.update_lvar_env { falsy_env }
                end

                clause_constr = when_constr.update_lvar_env {|env| env.join(*test_envs) }
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
                  var_name = assignment.children[0].name
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
                         each = checker.factory.interface(collection_type, private: true).methods[:each]
                         method_type = (each&.method_types || []).find {|type| type.block && type.block.type.params.first_param }
                         method_type&.yield_self do |method_type|
                           method_type.block.type.params.first_param&.type
                         end
                       end

            if var_type
              if body
                body_constr = constr.with_updated_context(
                  lvar_env: constr.context.lvar_env.assign(asgn.children[0].name, node: asgn, type: var_type)
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
                Errors::NoMethod.new(
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
            cond_type, constr = synthesize(cond)

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
              typing.add_error(Errors::IncompatibleAssignment.new(
                node: node,
                lhs_type: type,
                rhs_type: rhs_type,
                result: result)
              )
            end
          end

        when :gvar
          yield_self do
            name = node.children.first
            type = type_env.get(gvar: name) do
              typing.add_error Errors::FallbackAny.new(node: node)
            end

            add_typing(node, type: type)
          end

        when :block_pass
          yield_self do
            value = node.children[0]

            if hint.is_a?(AST::Types::Proc) && value.type == :sym
              if hint.one_arg?
                # Assumes Symbol#to_proc implementation
                param_type = hint.params.required[0]
                interface = checker.factory.interface(param_type, private: true)
                method = interface.methods[value.children[0]]
                if method
                  return_types = method.method_types.select {|method_type|
                    method_type.params.each_type.count == 0
                  }.map(&:return_type)

                  unless return_types.empty?
                    type = AST::Types::Proc.new(params: Interface::Function::Params.empty.update(required: [param_type]),
                                                return_type: AST::Types::Union.build(types: return_types))
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
                Errors::IncompatibleAssignment.new(node: node,
                                                   lhs_type: var_type,
                                                   rhs_type: type,
                                                   result: result)
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
            Steep.logger.warn { "Unsupported node #{node.type} (#{node.location.expression.source_buffer.name}:#{node.location.expression.line})" }

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
          raise "Unexpected node: #{node.inspect}, #{node.location.expression}"

        end.tap do |pair|
          unless pair.is_a?(Pair) && !pair.type.is_a?(Pair)
            # Steep.logger.error { "result = #{pair.inspect}" }
            # Steep.logger.error { "node = #{node.type}" }
            raise "#synthesize should return an instance of Pair: #{pair.class}, node=#{node.inspect}"
          end
        end
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
      ivar_type = type_env.assign(ivar: name, type: rhs_type, self_type: self_type) do |error|
        case error
        when Subtyping::Result::Failure
          type = type_env.get(ivar: name)
          typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                              lhs_type: type,
                                                              rhs_type: rhs_type,
                                                              result: error))
        when nil
          fallback_to_any node
        end
      end
      add_typing(node, type: ivar_type)
    end

    def masgn_lhs?(lhs)
      lhs.children.all? do |a|
        asgn_type = if a.type == :splat
                      a.children[0].type
                    else
                      a.type
                    end
        asgn_type == :lvasgn || asgn_type == :ivasgn
      end
    end

    def lvasgn(node, type)
      name = node.children[0].name
      env = context.lvar_env.assign(name, node: node, type: type) do |declared_type, type, result|
        typing.add_error(
          Errors::IncompatibleAssignment.new(node: node,
                                             lhs_type: declared_type,
                                             rhs_type: type,
                                             result: result)
        )
      end

      add_typing(node, type: type, constr: with_updated_context(lvar_env: env))
    end

    def ivasgn(node, type)
      ivar = node.children[0]

      type_env.assign(ivar: ivar, type: type, self_type: self_type) do |error|
        case error
        when Subtyping::Result::Failure
          var_type = type_env.get(ivar: ivar)
          typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                              lhs_type: var_type,
                                                              rhs_type: type,
                                                              result: error))
        when nil
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
            case asgn.children[0].type
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

    def type_lambda(node, block_params:, block_body:, type_hint:)
      block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)
      params = TypeInference::BlockParams.from_node(block_params, annotations: block_annotations)

      case type_hint
      when AST::Types::Proc
        params_hint = type_hint.params
        return_hint = type_hint.return_type
      end

      block_constr = for_block(
        block_params: params,
        block_param_hint: params_hint,
        block_annotations: block_annotations,
        node_type_hint: nil
      )

      block_constr.typing.add_context_for_body(node, context: block_constr.context)

      params.params.each do |param|
        _, block_constr = block_constr.synthesize(param.node, hint: param.type)
      end

      if block_body
        return_type = block_constr.synthesize_block(
          node: node,
          block_body: block_body,
          topdown_hint: true,
          block_type_hint: return_hint
        ) do |error|
          typing.add_error(error)
        end
      else
        return_type = AST::Builtin.any_type
      end

      block_type = AST::Types::Proc.new(
        params: params_hint || params.params_type,
        return_type: return_type
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
        args = TypeInference::SendArgs.from_nodes(arguments)
        call, constr = type_method_call(node,
                                        method: method,
                                        method_name: method_name,
                                        args: args,
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
          error = Errors::UnresolvedOverloading.new(
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
            ) do |error|
              constr.typing.add_error(error)
            end
          end
        end

        constr.add_call(call)
      else
        add_call(
          TypeInference::MethodCall::NoMethodError.new(
            node: node,
            context: context.method_context,
            method_name: method_name,
            receiver_type: receiver_type,
            error: Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
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

                     when AST::Types::Void, AST::Types::Bot, AST::Types::Top, AST::Types::Var
                       constr = constr.synthesize_children(node, skips: [receiver])
                       constr.add_call(
                         TypeInference::MethodCall::NoMethodError.new(
                           node: node,
                           context: context.method_context,
                           method_name: method_name,
                           receiver_type: receiver_type,
                           error: Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
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
                             error: Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
                           )
                         )
                       else
                         interface = checker.factory.interface(expanded_self,
                                                               private: !receiver,
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
                       interface = checker.factory.interface(receiver_type,
                                                             private: !receiver,
                                                             self_type: receiver_type)

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
    rescue => exn
      case exn
      when RBS::NoTypeFoundError, RBS::NoMixinFoundError, RBS::NoSuperclassFoundError, RBS::InvalidTypeApplicationError
        # ignore known RBS errors.
      else
        Steep.log_error(exn, message: "Unexpected error in #type_send: #{exn.message} (#{exn.class})")
      end

      error = Errors::UnexpectedError.new(node: node, error: exn)

      type_any_rec(node)

      add_call(
        TypeInference::MethodCall::Error.new(
          node: node,
          context: context.method_context,
          method_name: method_name,
          receiver_type: receiver_type,
          errors: [error]
        )
      )
    end

    def expand_self(type)
      if type.is_a?(AST::Types::Self) && self_type
        self_type
      else
        type
      end
    end

    def type_method_call(node, method_name:, receiver_type:, method:, args:, block_params:, block_body:, topdown_hint:)
      node_range = node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }

      results = method.method_types.flat_map do |method_type|
        Steep.logger.tagged method_type.to_s do
          zips = args.zips(method_type.params, method_type.block&.type)

          zips.map do |arg_pairs|
            typing.new_child(node_range) do |child_typing|
              self.with_new_typing(child_typing).try_method_type(
                node,
                receiver_type: receiver_type,
                method_name: method_name,
                method_type: method_type,
                args: args,
                arg_pairs: arg_pairs,
                block_params: block_params,
                block_body: block_body,
                topdown_hint: topdown_hint
              )
            end
          end
        end
      end

      case
      when results.empty?
        method_type = method.method_types.last
        all_decls = method.method_types.each.with_object(Set[]) do |method_type, set|
          set.merge(method_type.method_decls)
        end
        error = Errors::IncompatibleArguments.new(node: node, receiver_type: receiver_type, method_type: method_type)
        call = TypeInference::MethodCall::Error.new(
          node: node,
          context: context.method_context,
          method_name: method_name,
          receiver_type: receiver_type,
          return_type: method_type.return_type,
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

    def check_keyword_arg(receiver_type:, node:, method_type:, constraints:)
      params = method_type.params

      case node.type
      when :hash
        keyword_hash_type = AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type,
                                                             AST::Builtin.any_type)
        add_typing node, type: keyword_hash_type

        given_keys = Set.new()

        node.children.each do |element|
          case element.type
          when :pair
            key_node, value_node = element.children

            case key_node.type
            when :sym
              key_symbol = key_node.children[0]
              keyword_type = case
                             when params.required_keywords.key?(key_symbol)
                               params.required_keywords[key_symbol]
                             when params.optional_keywords.key?(key_symbol)
                               AST::Types::Union.build(
                                 types: [params.optional_keywords[key_symbol],
                                         AST::Builtin.nil_type]
                               )
                             when params.rest_keywords
                               params.rest_keywords
                             end

              add_typing key_node, type: AST::Builtin::Symbol.instance_type

              given_keys << key_symbol

              if keyword_type
                check(value_node, keyword_type, constraints: constraints) do |expected, actual, result|
                  return Errors::IncompatibleAssignment.new(
                    node: value_node,
                    lhs_type: expected,
                    rhs_type: actual,
                    result: result
                  )
                end
              else
                synthesize(value_node)
              end

            else
              check(key_node, AST::Builtin::Symbol.instance_type, constraints: constraints) do |expected, actual, result|
                return Errors::IncompatibleAssignment.new(
                  node: key_node,
                  lhs_type: expected,
                  rhs_type: actual,
                  result: result
                )
              end
            end

          when :kwsplat
            Steep.logger.warn("Keyword arg with kwsplat(**) node are not supported.")

            check(element.children[0], keyword_hash_type, constraints: constraints) do |expected, actual, result|
              return Errors::IncompatibleAssignment.new(
                node: node,
                lhs_type: expected,
                rhs_type: actual,
                result: result
              )
            end

            given_keys = true
          end
        end

        case given_keys
        when Set
          missing_keywords = Set.new(params.required_keywords.keys) - given_keys
          unless missing_keywords.empty?
            return Errors::MissingKeyword.new(node: node,
                                              missing_keywords: missing_keywords)
          end

          extra_keywords = given_keys - Set.new(params.required_keywords.keys) - Set.new(params.optional_keywords.keys)
          if extra_keywords.any? && !params.rest_keywords
            return Errors::UnexpectedKeyword.new(node: node,
                                                 unexpected_keywords: extra_keywords)
          end
        end
      else
        if params.rest_keywords
          Steep.logger.warn("Method call with rest keywords type is detected. Rough approximation to be improved.")

          value_types = params.required_keywords.values +
            params.optional_keywords.values.map {|type| AST::Types::Union.build(types: [type, AST::Builtin.nil_type])} +
            [params.rest_keywords]

          hash_type = AST::Builtin::Hash.instance_type(
            AST::Builtin::Symbol.instance_type,
            AST::Types::Union.build(types: value_types)
          )
        else
          hash_elements = params.required_keywords.merge(
            method_type.params.optional_keywords.transform_values do |type|
              AST::Types::Union.build(types: [type, AST::Builtin.nil_type])
            end
          )

          hash_type = AST::Types::Record.new(elements: hash_elements)
        end

        node_type = synthesize(node, hint: hash_type).type

        check_relation(sub_type: node_type, super_type: hash_type).else do
          return Errors::ArgumentTypeMismatch.new(
            node: node,
            receiver_type: receiver_type,
            expected: hash_type,
            actual: node_type
          )
        end
      end

      nil
    end

    def try_method_type(node, receiver_type:, method_name:, method_type:, args:, arg_pairs:, block_params:, block_body:, topdown_hint:)
      fresh_types = method_type.type_params.map {|x| AST::Types::Var.fresh(x)}
      fresh_vars = Set.new(fresh_types.map(&:name))
      instantiation = Interface::Substitution.build(method_type.type_params, fresh_types)

      constr = self

      method_type = method_type.instantiate(instantiation)

      constraints = Subtyping::Constraints.new(unknowns: fresh_types.map(&:name))
      variance = Subtyping::VariableVariance.from_method_type(method_type)
      occurence = Subtyping::VariableOccurence.from_method_type(method_type)

      errors = []

      arg_pairs.each do |pair|
        case pair
        when Array
          arg_node, param_type = pair
          param_type = param_type.subst(instantiation)

          arg_type, constr = if arg_node.type == :splat
                               constr.synthesize(arg_node.children[0])
                             else
                               constr.synthesize(arg_node, hint: topdown_hint ? param_type : nil)
                             end

          check_relation(sub_type: arg_type, super_type: param_type, constraints: constraints).else do
            errors << Errors::ArgumentTypeMismatch.new(node: arg_node,
                                                       receiver_type: receiver_type,
                                                       expected: param_type,
                                                       actual: arg_type)
          end
        else
          # keyword
          result = constr.check_keyword_arg(receiver_type: receiver_type,
                                            node: pair,
                                            method_type: method_type,
                                            constraints: constraints)

          if result.is_a?(Errors::Base)
            errors << result
          end
        end
      end

      if block_params
        # block is given
        block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)
        block_params_ = TypeInference::BlockParams.from_node(block_params, annotations: block_annotations)

        if method_type.block
          pairs = method_type.block && block_params_&.zip(method_type.block.type.params)

          if pairs
            begin
              block_constr = constr.for_block(
                block_params: block_params_,
                block_param_hint: method_type.block.type.params,
                block_annotations: block_annotations,
                node_type_hint: method_type.return_type
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
                    error = Errors::IncompatibleAssignment.new(
                      node: param.node,
                      lhs_type: param.type,
                      rhs_type: type,
                      result: result
                    )
                    errors << error
                  end
                end
              end

              s = constraints.solution(
                checker,
                self_type: self_type,
                variance: variance,
                variables: method_type.params.free_variables + method_type.block.type.params.free_variables
              )
              method_type = method_type.subst(s)
              block_constr = block_constr.update_lvar_env {|env| env.subst(s) }
              if block_body
                block_body_type = block_constr.synthesize_block(
                  node: node,
                  block_type_hint: method_type.block.type.return_type,
                  block_body: block_body,
                  topdown_hint: topdown_hint
                ) do |error|
                  errors << error
                end
              else
                block_body_type = AST::Builtin.nil_type
              end

              result = check_relation(sub_type: block_body_type,
                                      super_type: method_type.block.type.return_type,
                                      constraints: constraints)

              case result
              when Subtyping::Result::Success
                s = constraints.solution(checker, self_type: self_type, variance: variance, variables: fresh_vars)
                method_type = method_type.subst(s)

                return_type = method_type.return_type
                if break_type = block_annotations.break_type
                  return_type = union_type(break_type, return_type)
                end

              when Subtyping::Result::Failure
                block_type = AST::Types::Proc.new(
                  params: method_type.block.type.params || block_params.params_type,
                  return_type: block_body_type
                )
                errors << Errors::BlockTypeMismatch.new(node: node,
                                                        expected: method_type.block.type,
                                                        actual: block_type,
                                                        result: result)

                return_type = method_type.return_type
              end

              block_constr.typing.save!
            rescue Subtyping::Constraints::UnsatisfiableConstraint => exn
              errors << Errors::UnsatisfiableConstraint.new(
                node: node,
                method_type: method_type,
                var: exn.var,
                sub_type: exn.sub_type,
                super_type: exn.super_type,
                result: exn.result
              )

              constr.type_block_without_hint(node: node, block_annotations: block_annotations, block_params: block_params_, block_body: block_body) do |error|
                errors << error
              end

              s = Interface::Substitution.build(method_type.free_variables,
                                                Array.new(method_type.free_variables.size, AST::Builtin.any_type))
              method_type = method_type.subst(s)
            end
          else
            errors << Errors::UnsupportedSyntax.new(
              node: block_params,
              message: "Unsupported block params pattern, probably masgn?"
            )

            s = constraints.solution(checker, variance: variance, variables: fresh_vars, self_type: self_type)
            method_type = method_type.subst(s)
          end
        else
          # Block is given but method doesn't accept
          #
          constr.type_block_without_hint(node: node, block_annotations: block_annotations, block_params: block_params_, block_body: block_body) do |error|
            errors << error
          end

          errors << Errors::UnexpectedBlockGiven.new(
            node: node,
            method_type: method_type
          )
        end
      else
        # block is not given
        if (!method_type.block || method_type.block.optional?)
          # Method call without block is allowed
          unless args.block_pass_arg
            # OK, without block
            s = constraints.solution(checker, variance: variance, variables: fresh_vars, self_type: self_type)
            method_type = method_type.subst(s)
          else
            # &block arg is given
            s = constraints.solution(checker, variance: variance, variables: fresh_vars, self_type: self_type)
            method_type = method_type.subst(s)

            errors << Errors::UnexpectedBlockGiven.new(
              node: node,
              method_type: method_type
            )
          end
        else
          unless args.block_pass_arg
            # Required block is missing
            errors << Errors::RequiredBlockMissing.new(
              node: node,
              method_type: method_type
            )

            s = constraints.solution(checker, variance: variance, variables: fresh_vars, self_type: self_type)
            method_type = method_type.subst(s)
          else
            begin
              method_type = method_type.subst(constraints.solution(checker, self_type: self_type, variance: variance, variables: occurence.params))
              block_type, constr = constr.synthesize(args.block_pass_arg, hint: topdown_hint ? method_type.block.type : nil)
              result = check_relation(
                sub_type: block_type,
                super_type: method_type.block.yield_self {|expected_block|
                  if expected_block.optional?
                    AST::Builtin.optional(expected_block.type)
                  else
                    expected_block.type
                  end
                },
                constraints: constraints
              )

              result.else do |result|
                errors << Errors::BlockTypeMismatch.new(node: node,
                                                        expected: method_type.block.type,
                                                        actual: block_type,
                                                        result: result)
              end

              method_type = method_type.subst(constraints.solution(checker, self_type: self_type, variance: variance, variables: method_type.free_variables))
            end
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
                 return_type: return_type || method_type.return_type,
                 method_decls: method_type.method_decls
               )
             else
               TypeInference::MethodCall::Error.new(
                 node: node,
                 context: context.method_context,
                 receiver_type: receiver_type,
                 method_name: method_name,
                 return_type: return_type || method_type.return_type,
                 method_decls: method_type.method_decls,
                 errors: errors
               )
             end

      [
        call,
        constr
      ]
    end

    def type_block_without_hint(node:, block_annotations:, block_params:, block_body:, &block)
      block_constr = for_block(
        block_params: block_params,
        block_param_hint: nil,
        block_annotations: block_annotations,
        node_type_hint: nil
      )

      block_constr.typing.add_context_for_body(node, context: block_constr.context)

      block_params.params.each do |param|
        _, block_constr = block_constr.synthesize(param.node, hint: param.type)
      end

      block_constr.synthesize_block(node: node, block_type_hint: nil, block_body: block_body, topdown_hint: false, &block)
    end

    def for_block(block_params:, block_param_hint:, block_annotations:, node_type_hint:)
      block_param_pairs = block_param_hint && block_params.zip(block_param_hint)

      param_types_hash = {}
      if block_param_pairs
        block_param_pairs.each do |param, type|
          var_name = param.var.name
          param_types_hash[var_name] = type
        end
      else
        block_params.each do |param|
          var_name = param.var.name
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
        body_type: block_annotations.block_type
      )
      break_context = TypeInference::Context::BreakContext.new(
        break_type: break_type,
        next_type: block_context.body_type
      )

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
          self_type: block_annotations.self_type || self_type,
          type_env: type_env.dup,
          lvar_env: lvar_env,
          call_context: self.context.call_context
        )
      )
    end

    def synthesize_block(node:, block_type_hint:, block_body:, topdown_hint:)
      if block_body
        body_type, _, context =
          if (body_type = block_context.body_type)
            check(block_body, body_type) do |expected, actual, result|
              error = Errors::BlockTypeMismatch.new(node: block_body,
                                                    expected: expected,
                                                    actual: actual,
                                                    result: result)
              yield(error) if block_given?
            end
          else
            synthesize(block_body, hint: topdown_hint ? block_type_hint : nil)
          end

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

    def self.parameter_types(nodes, type)
      nodes = nodes.dup

      env = {}

      type.params.required.each do |type|
        a = nodes.first
        if a&.type == :arg
          env[a.children.first] = type
          nodes.shift
        else
          break
        end
      end

      type.params.optional.each do |type|
        a = nodes.first

        if a&.type == :optarg
          env[a.children.first] = type
          nodes.shift
        else
          break
        end
      end

      if type.params.rest
        a = nodes.first
        if a&.type == :restarg
          env[a.children.first] = AST::Builtin::Array.instance_type(type.params.rest)
          nodes.shift
        end
      end

      nodes.each do |node|
        if node.type == :kwarg
          name = node.children[0]
          ty = type.params.required_keywords[name.name]
          env[name] = ty if ty
        end

        if node.type == :kwoptarg
          name = node.children[0]
          ty = type.params.optional_keywords[name.name]
          env[name] = ty if ty
        end

        if node.type == :kwrestarg
          ty = type.params.rest_keywords
          if ty
            env[node.children[0]] = AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type, ty)
          end
        end
      end

      env
    end

    def self.valid_parameter_env?(env, nodes, params)
      env.size == nodes.size && env.size == params.size
    end

    def current_namespace
      module_context&.current_namespace || AST::Namespace.root
    end

    def nested_namespace_for_module(module_name)
      if module_name.namespace.relative?
        (current_namespace + module_name.namespace).append(module_name.name)
      else
        module_name
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
            typing.add_error Errors::MethodDefinitionMissing.new(node: node,
                                                                 module_name: module_name.name,
                                                                 kind: :instance,
                                                                 missing_method: method_name)
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
            typing.add_error Errors::MethodDefinitionMissing.new(node: node,
                                                                 module_name: module_name.name,
                                                                 kind: :module,
                                                                 missing_method: method_name)
          end
        end
      end

      annotations.instance_dynamics.each do |method_name|
        unless expected_instance_method_names.member?(method_name)
          typing.add_error Errors::UnexpectedDynamicMethod.new(node: node,
                                                               module_name: module_name.name,
                                                               method_name: method_name)
        end
      end
      annotations.module_dynamics.each do |method_name|
        unless expected_module_method_names.member?(method_name)
          typing.add_error Errors::UnexpectedDynamicMethod.new(node: node,
                                                               module_name: module_name.name,
                                                               method_name: method_name)
        end
      end
    end

    def flatten_const_name(node)
      path = []

      while node
        case node.type
        when :const, :casgn
          path.unshift(node.children[1])
          node = node.children[0]
        when :cbase
          path.unshift("")
          break
        else
          return nil
        end
      end

      path.join("::").to_sym
    end

    def fallback_to_any(node)
      if block_given?
        typing.add_error yield
      else
        typing.add_error Errors::FallbackAny.new(node: node)
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
    end

    def fallback_any_rec(node)
      fallback_to_any(node) unless typing.has_type?(node)

      each_child_node(node) do |child|
        fallback_any_rec(child)
      end

      typing.type_of(node: node)
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

    def self.value_variables(node)
      case node&.type
      when :lvar
        Set.new([node.children.first.name])
      when :lvasgn
        Set.new([node.children.first.name]) + value_variables(node.children[1])
      when :begin
        value_variables(node.children.last)
      else
        Set.new
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

    def select_super_type(sub_type, super_type)
      if super_type
        result = check_relation(sub_type: sub_type, super_type: super_type)

        if result.success?
          super_type
        else
          if block_given?
            yield result
          else
            sub_type
          end
        end
      else
        sub_type
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

    def try_tuple_type(node, hint)
      if node.children.size != hint.types.size
        return
      end

      constr = self
      element_types = []

      each_child_node(node).with_index do |child, index|
        type, constr = constr.synthesize(child, hint: hint.types[index])
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

    def try_hash_type(node, hint)
      hint = expand_alias(hint)

      case hint
      when AST::Types::Record
        typing.new_child(node.loc.expression.yield_self {|l| l.begin_pos..l.end_pos }) do |child_typing|
          new_construction = with_new_typing(child_typing)
          elements = {}

          each_child_node(node) do |child|
            case child.type
            when :pair
              key, value = child.children

              key_value = case key.type
                          when :str, :int, :sym
                            key.children[0]
                          else
                            return nil
                          end

              value_hint = hint.elements[key_value]
              value_type = new_construction.synthesize(value, hint: value_hint).type

              if value_hint
                if check_relation(sub_type: value_type, super_type: value_hint).success?
                  value_type = value_hint
                end
              end

              elements[key_value] = value_type
            else
              return nil
            end
          end

          child_typing.save!

          hash = AST::Types::Record.new(elements: elements)
          add_typing(node, type: hash)
        end
      when AST::Types::Union
        hint.types.each do |type|
          if pair = try_hash_type(node, type)
            return pair
          end
        end
        nil
      end
    end
  end
end
