module Steep
  class TypeConstruction
    attr_reader :checker
    attr_reader :source
    attr_reader :annotations
    attr_reader :typing
    attr_reader :type_env

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

    def check_relation(sub_type:, super_type:, constraints: Subtyping::Constraints.empty)
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
                                     .map {|method_type| checker.factory.method_type(method_type, self_type: self_type) }
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
          var_types[block_arg.children[0].name] = block_type
        end
      end

      super_method = if definition
                       if (this_method = definition.methods[method_name])
                         if module_context&.class_name == checker.factory.type_name(this_method.defined_in.name.absolute!)
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

      if var_types
        var_types.each do |name, type|
          type_env.set(lvar: name, type: type)
        end
      end

      if definition
        definition.instance_variables.each do |name, decl|
          type_env.set(ivar: name, type: checker.factory.type(decl.type))
        end
      end

      type_env = type_env.with_annotations(
        lvar_types: annots.lvar_types,
        ivar_types: annots.ivar_types,
        const_types: annots.const_types,
        self_type: annots.self_type || self_type
      )

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
          type_env: type_env
        ),
        typing: typing,
      )
    end

    def for_module(node)
      new_module_name = Names::Module.from_node(node.children.first) or raise "Unexpected module name: #{node.children.first}"
      new_namespace = nested_namespace_for_module(new_module_name)

      annots = source.annotations(block: node, factory: checker.factory, current_module: new_namespace)
      module_type = AST::Builtin::Module.instance_type

      implement_module_name = yield_self do
        if (annotation = annots.implement_module_annotation)
          absolute_name(annotation.name.name).yield_self do |absolute_name|
            if checker.factory.module_name?(absolute_name)
              AST::Annotation::Implements::Module.new(name: absolute_name,
                                                      args: annotation.name.args)
            else
              Steep.logger.error "Unknown module name given to @implements: #{annotation.name.name}"
              nil
            end
          end
        else
          absolute_name(new_module_name).yield_self do |absolute_name|
            if checker.factory.module_name?(absolute_name)
              absolute_name_ = checker.factory.type_name_1(absolute_name)
              decl = checker.factory.env.find_class(absolute_name_)
              AST::Annotation::Implements::Module.new(name: absolute_name,
                                                      args: decl.type_params.each.map(&:name))
            end
          end
        end
      end

      if implement_module_name
        module_name = implement_module_name.name
        module_args = implement_module_name.args.map {|x| AST::Types::Var.new(name: x)}

        type_name_ = checker.factory.type_name_1(implement_module_name.name)
        module_decl = checker.factory.definition_builder.env.find_class(type_name_)
        instance_def = checker.factory.definition_builder.build_instance(type_name_)
        module_def = checker.factory.definition_builder.build_singleton(type_name_)

        instance_type = AST::Types::Intersection.build(
          types: [
            AST::Types::Name::Instance.new(name: module_name, args: module_args),
            AST::Builtin::Object.instance_type,
            module_decl.self_type&.yield_self {|ty|
              absolute_type = checker.factory.env.absolute_type(ty, namespace: module_decl.name.absolute!.namespace)
              checker.factory.type(absolute_type)
            }
          ].compact
        )

        module_type = AST::Types::Name::Class.new(name: module_name, constructor: nil)
      end

      if annots.instance_type
        instance_type = annots.instance_type
      end

      if annots.module_type
        module_type = annots.module_type
      end

      const_context = if new_namespace.empty?
                        nil
                      else
                        Names::Module.new(name: new_namespace.path.last, namespace: new_namespace.parent)
                      end
      module_const_env = TypeInference::ConstantEnv.new(factory: checker.factory, context: const_context)

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
          type_env: module_type_env
        )
      )
    end

    def for_class(node)
      new_class_name = Names::Module.from_node(node.children.first) or raise "Unexpected class name: #{node.children.first}"
      super_class_name = node.children[1] && Names::Module.from_node(node.children[1])
      new_namespace = nested_namespace_for_module(new_class_name)

      annots = source.annotations(block: node, factory: checker.factory, current_module: new_namespace)

      implement_module_name = yield_self do
        if (annotation = annots.implement_module_annotation)
          absolute_name(annotation.name.name).yield_self do |absolute_name|
            if checker.factory.class_name?(absolute_name)
              AST::Annotation::Implements::Module.new(name: absolute_name,
                                                      args: annotation.name.args)
            else
              Steep.logger.error "Unknown class name given to @implements: #{annotation.name.name}"
              nil
            end
          end
        else
          name = nil
          name ||= absolute_name(new_class_name).yield_self do |absolute_name|
            absolute_name if checker.factory.class_name?(absolute_name)
          end
          name ||= super_class_name && absolute_name(super_class_name).yield_self do |absolute_name|
            absolute_name if checker.factory.class_name?(absolute_name)
          end

          if name
            absolute_name_ = checker.factory.type_name_1(name)
            decl = checker.factory.env.find_class(absolute_name_)
            AST::Annotation::Implements::Module.new(name: name,
                                                    args: decl.type_params.each.map(&:name))
          end
        end
      end

      if annots.implement_module_annotation
        new_class_name = implement_module_name.name
      end

      if implement_module_name
        class_name = implement_module_name.name
        class_args = implement_module_name.args.map {|x| AST::Types::Var.new(name: x)}

        type_name_ = checker.factory.type_name_1(implement_module_name.name)
        instance_def = checker.factory.definition_builder.build_instance(type_name_)
        module_def = checker.factory.definition_builder.build_singleton(type_name_)

        instance_type = AST::Types::Name::Instance.new(name: class_name, args: class_args)
        module_type = AST::Types::Name::Class.new(name: class_name, constructor: nil)
      end

      if annots.instance_type
        instance_type = annots.instance_type
      end

      if annots.module_type
        module_type = annots.module_type
      end

      const_context = if new_namespace.empty?
                        nil
                      else
                        Names::Module.new(name: new_namespace.path.last, namespace: new_namespace.parent)
                      end
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


      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        typing: typing,
        context: TypeInference::Context.new(
          method_context: nil,
          block_context: nil,
          module_context: module_context,
          break_context: nil,
          self_type: module_context.module_type,
          type_env: class_type_env
        )
      )
    end

    def for_branch(node, truthy_vars: Set.new, type_case_override: nil, break_context: context.break_context)
      annots = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)

      lvar_types = self.type_env.lvar_types.each.with_object({}) do |(var, type), env|
        if truthy_vars.member?(var)
          env[var] = unwrap(type)
        else
          env[var] = type
        end
      end

      type_env = self.type_env.with_annotations(lvar_types: lvar_types, self_type: self_type) do |var, relation, result|
        raise "Unexpected annotate failure: #{relation}"
      end

      if type_case_override
        type_env = type_env.with_annotations(lvar_types: type_case_override, self_type: self_type) do |var, relation, result|
          typing.add_error(
            Errors::IncompatibleTypeCase.new(node: node,
                                             var_name: var,
                                             relation: relation,
                                             result: result)
          )
        end
      end

      type_env = type_env.with_annotations(
        lvar_types: annots.lvar_types,
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

      with(context: context.with(type_env: type_env, break_context: break_context))
    end

    NOTHING = ::Object.new

    def with(annotations: NOTHING, context: NOTHING)
      self.class.new(
        checker: checker,
        source: source,
        annotations: annotations.equal?(NOTHING) ? self.annotations : annotations,
        typing: typing,
        context: context.equal?(NOTHING) ? self.context : context
      )
    end

    def synthesize(node, hint: nil)
      Steep.logger.tagged "synthesize:(#{node.location.expression.to_s.split(/:/, 2).last})" do
        Steep.logger.debug node.type
        case node.type
        when :begin, :kwbegin
          yield_self do
            *mid_nodes, last_node = each_child_node(node).to_a
            if last_node
              pairs = mid_nodes.map do |child|
                synthesize(child)
              end

              last_pair = synthesize(last_node, hint: hint)
              pairs << last_pair

              type = if pairs.any? {|pair| pair.type.is_a?(AST::Types::Bot) }
                       AST::Builtin.bottom_type
                     else
                       last_pair.type
                     end

              typing.add_typing(node, type, context)
            else
              typing.add_typing(node, AST::Builtin.nil_type, context)
            end
          end

        when :lvasgn
          yield_self do
            var = node.children[0]
            rhs = node.children[1]

            case var.name
            when :_, :__any__
              synthesize(rhs, hint: AST::Builtin.any_type)
              typing.add_typing(node, AST::Builtin.any_type, context)
            when :__skip__
              typing.add_typing(node, AST::Builtin.any_type, context)
            else
              type_assignment(var, rhs, node, hint: hint)
            end
          end

        when :lvar
          yield_self do
            var = node.children[0]
            type = type_env.get(lvar: var.name) do
              fallback_to_any(node).type
            end

            typing.add_typing node, type, context
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
            typing.add_typing(node, type, context)
          end

        when :send
          yield_self do
            if self_class?(node)
              module_type = expand_alias(module_context.module_type)
              type = if module_type.is_a?(AST::Types::Name::Class)
                       AST::Types::Name::Class.new(name: module_type.name, constructor: method_context.constructor)
                     else
                       module_type
                     end

              typing.add_typing(node, type, context)
            else
              type_send(node, send_node: node, block_params: nil, block_body: nil)
            end
          end

        when :csend
          yield_self do
            type = if self_class?(node)
                     module_type = expand_alias(module_context.module_type)
                     type = if module_type.is_a?(AST::Types::Name::Class)
                              AST::Types::Name::Class.new(name: module_type.name, constructor: method_context.constructor)
                            else
                              module_type
                            end
                     typing.add_typing(node, type, context).type
                   else
                     type_send(node, send_node: node, block_params: nil, block_body: nil, unwrap: true).type
                   end

            typing.add_typing(node,
                              union_type(type, AST::Builtin.nil_type),
                              context)
          end

        when :match_with_lvasgn
          each_child_node(node) do |child|
            synthesize(child)
          end
          typing.add_typing(node, AST::Builtin.any_type, context)

        when :op_asgn
          yield_self do
            lhs, op, rhs = node.children

            synthesize(rhs)

            lhs_type = case lhs.type
                       when :lvasgn
                         type_env.get(lvar: lhs.children.first.name) do
                           break
                         end
                       when :ivasgn
                         type_env.get(ivar: lhs.children.first) do
                           break
                         end
                       else
                         Steep.logger.error("Unexpected op_asgn lhs: #{lhs.type}")
                         nil
                       end

            case
            when lhs_type == AST::Builtin.any_type
              typing.add_typing(node, lhs_type, context)
            when !lhs_type
              fallback_to_any(node)
            else
              lhs_interface = checker.factory.interface(lhs_type, private: false)
              op_method = lhs_interface.methods[op]

              if op_method
                args = TypeInference::SendArgs.from_nodes([rhs])
                return_type, _ = type_method_call(node,
                                                  receiver_type: lhs_type,
                                                  method_name: op,
                                                  method: op_method,
                                                  args: args,
                                                  block_params: nil,
                                                  block_body: nil,
                                                  topdown_hint: true)

                result = check_relation(sub_type: return_type, super_type: lhs_type)
                if result.failure?
                  typing.add_error(
                    Errors::IncompatibleAssignment.new(
                      node: node,
                      lhs_type: lhs_type,
                      rhs_type: return_type,
                      result: result
                    )
                  )
                end
              else
                typing.add_error Errors::NoMethod.new(node: node, method: op, type: expand_self(lhs_type))
              end

              typing.add_typing(node, lhs_type, context)
            end
          end

        when :super
          yield_self do
            if self_type && method_context&.method
              if method_context.super_method
                each_child_node(node) do |child|
                  synthesize(child)
                end

                super_method = Interface::Interface::Combination.overload(
                  method_context.super_method.method_types.map {|method_type|
                    checker.factory.method_type(method_type, self_type: self_type)
                  },
                  incompatible: false
                )
                args = TypeInference::SendArgs.from_nodes(node.children.dup)

                return_type, _ = type_method_call(node,
                                                  receiver_type: self_type,
                                                  method_name: method_context.name,
                                                  method: super_method,
                                                  args: args,
                                                  block_params: nil,
                                                  block_body: nil,
                                                  topdown_hint: true)

                typing.add_typing node, return_type, context
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
          new = for_new_method(node.children[0],
                               node,
                               args: node.children[1].children,
                               self_type: module_context&.instance_type,
                               definition: module_context&.instance_definition)

          each_child_node(node.children[1]) do |arg|
            new.synthesize(arg)
          end

          if node.children[2]
            return_type = expand_alias(new.method_context&.return_type)
            if return_type && !return_type.is_a?(AST::Types::Void)
              new.check(node.children[2], return_type) do |_, actual_type, result|
                typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                    expected: new.method_context&.return_type,
                                                                    actual: actual_type,
                                                                    result: result))
              end
            else
              new.synthesize(node.children[2])
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
          end

          if module_context
            module_context.defined_instance_methods << node.children[0]
          end

          typing.add_typing(node, AST::Builtin.any_type, new.context)

        when :defs
          synthesize(node.children[0]).tap do |pair|
            self_type = pair.type
            self_type = expand_self(self_type)
            definition = case self_type
                         when AST::Types::Name::Instance
                           name = checker.factory.type_name_1(self_type.name)
                           checker.factory.definition_builder.build_singleton(name)
                         when AST::Types::Name::Module, AST::Types::Name::Class
                           name = checker.factory.type_name_1(self_type.name)
                           checker.factory.definition_builder.build_singleton(name)
                         end

            new = for_new_method(node.children[1],
                                 node,
                                 args: node.children[2].children,
                                 self_type: self_type,
                                 definition: definition)

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

          typing.add_typing(node, AST::Builtin::Symbol.instance_type, context)

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

            typing.add_typing(node, AST::Builtin.bottom_type, context)
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

          typing.add_typing(node, AST::Builtin.bottom_type, context)

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

          typing.add_typing(node, AST::Builtin.bottom_type, context)

        when :retry
          unless break_context
            typing.add_error Errors::UnexpectedJump.new(node: node)
          end
          typing.add_typing(node, AST::Builtin.bottom_type, context)

        when :arg, :kwarg, :procarg0
          yield_self do
            var = node.children[0]
            type = type_env.get(lvar: var.name) do
              fallback_to_any(node).type
            end
            typing.add_typing(node, type, context)
          end

        when :optarg, :kwoptarg
          yield_self do
            var = node.children[0]
            rhs = node.children[1]
            type_assignment(var, rhs, node, hint: hint)
          end

        when :restarg
          yield_self do
            var = node.children[0]
            type = type_env.get(lvar: var.name) do
              typing.add_error Errors::FallbackAny.new(node: node)
              AST::Builtin::Array.instance_type(AST::Builtin.any_type)
            end

            typing.add_typing(node, type, context)
          end

        when :kwrestarg
          yield_self do
            var = node.children[0]
            type = type_env.get(lvar: var.name) do
              typing.add_error Errors::FallbackAny.new(node: node)
              AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type, AST::Builtin.any_type)
            end

            typing.add_typing(node, type, context)
          end

        when :float
          typing.add_typing(node, AST::Builtin::Float.instance_type, context)

        when :nil
          typing.add_typing(node, AST::Builtin.nil_type, context)

        when :int
          yield_self do
            literal_type = expand_alias(hint) {|hint_| test_literal_type(node.children[0], hint_)}

            if literal_type
              typing.add_typing(node, literal_type, context)
            else
              typing.add_typing(node, AST::Builtin::Integer.instance_type, context)
            end
          end

        when :sym
          yield_self do
            literal_type = expand_alias(hint) {|hint_| test_literal_type(node.children[0], hint_)}

            if literal_type
              typing.add_typing(node, literal_type, context)
            else
              typing.add_typing(node, AST::Builtin::Symbol.instance_type, context)
            end
          end

        when :str
          yield_self do
            literal_type = expand_alias(hint) {|hint_| test_literal_type(node.children[0], hint_)}

            if literal_type
              typing.add_typing(node, literal_type, context)
            else
              typing.add_typing(node, AST::Builtin::String.instance_type, context)
            end
          end

        when :true, :false
          typing.add_typing(node, AST::Types::Boolean.new, context)

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
                key_types << synthesize(key).type.yield_self do |type|
                  select_super_type(type, key_hint)
                end
                value_types << synthesize(value).type.yield_self do |type|
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

            typing.add_typing(node, AST::Builtin::Hash.instance_type(key_type, value_type), context)
          end

        when :dstr, :xstr
          each_child_node(node) do |child|
            synthesize(child)
          end

          typing.add_typing(node, AST::Builtin::String.instance_type, context)

        when :dsym
          each_child_node(node) do |child|
            synthesize(child)
          end

          typing.add_typing(node, AST::Builtin::Symbol.instance_type, context)

        when :class
          yield_self do
            for_class(node).yield_self do |constructor|
              constructor.synthesize(node.children[2]) if node.children[2]

              if constructor.module_context&.implement_name && !namespace_module?(node)
                constructor.validate_method_definitions(node, constructor.module_context.implement_name)
              end

              typing.add_typing(node, AST::Builtin.nil_type, constructor.context)
            end
          end

        when :module
          yield_self do
            for_module(node).yield_self do |constructor|
              constructor.synthesize(node.children[1]) if node.children[1]

              if constructor.module_context&.implement_name && !namespace_module?(node)
                constructor.validate_method_definitions(node, constructor.module_context.implement_name)
              end

              typing.add_typing(node, AST::Builtin.nil_type, constructor.context)
            end
          end

        when :self
          typing.add_typing node, AST::Types::Self.new, context

        when :const
          const_name = Names::Module.from_node(node)
          if const_name
            type = type_env.get(const: const_name) do
              fallback_to_any(node)
            end
            typing.add_typing node, type, context
          else
            fallback_to_any node
          end

        when :casgn
          yield_self do
            const_name = Names::Module.from_node(node)
            if const_name
              value_type = synthesize(node.children.last).type
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

              typing.add_typing(node, type, context)
            else
              synthesize(node.children.last)
              fallback_to_any(node)
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

              typing.add_typing(node, block_type.type.return_type, context)
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
                  case method_type
                  when Ruby::Signature::MethodType
                    checker.factory.method_type(method_type, self_type: self_type).return_type
                  when :any
                    AST::Builtin.any_type
                  else
                    raise "Unexpected method_type: #{method_type.inspect}"
                  end
                }
                typing.add_typing(node, union_type(*types), context)
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
              typing.add_error Errors::FallbackAny.new(node: node) unless hint

              array_type = if hint
                             if check_relation(sub_type: AST::Builtin::Array.instance_type(AST::Builtin.any_type),
                                               super_type: hint).success?
                               hint
                             end
                           end

              typing.add_typing(node, array_type || AST::Builtin::Array.instance_type(AST::Builtin.any_type), context)
            else
              is_tuple = nil

              expand_alias(hint) do |hint|
                is_tuple = hint.is_a?(AST::Types::Tuple)
                is_tuple &&= node.children.all? {|child| child.type != :splat}
                is_tuple &&= node.children.size >= hint.types.size
                is_tuple &&= hint.types.map.with_index do |child_type, index|
                  child_node = node.children[index]
                  [synthesize(child_node, hint: child_type).type, child_type]
                end.all? do |node_type, hint_type|
                  result = check_relation(sub_type: node_type, super_type: hint_type)
                  result.success?
                end
              end

              if is_tuple
                array_type = hint
              else
                element_hint = expand_alias(hint) do |hint|
                  AST::Builtin::Array.instance_type?(hint) && hint.args[0]
                end

                element_types = node.children.flat_map do |e|
                  if e.type == :splat
                    Steep.logger.info "Typing of splat in array is incompatible with Ruby; it does not use #to_a method"
                    synthesize(e.children.first).type.yield_self do |type|
                      expand_alias(type) do |ty|
                        case ty
                        when AST::Types::Union
                          ty.types
                        else
                          [ty]
                        end
                      end
                    end.map do |type|
                      case
                      when AST::Builtin::Array.instance_type?(type)
                        type.args.first
                      when AST::Builtin::Range.instance_type?(type)
                        type.args.first
                      else
                        type
                      end
                    end
                  else
                    [select_super_type(synthesize(e).type, element_hint)]
                  end
                end
                array_type = AST::Builtin::Array.instance_type(AST::Types::Union.build(types: element_types))
              end

              typing.add_typing(node, array_type, context)
            end
          end

        when :and
          yield_self do
            left, right = node.children
            left_type = synthesize(left).type

            truthy_vars = TypeConstruction.truthy_variables(left)
            right_type, right_env = for_branch(right, truthy_vars: truthy_vars).yield_self do |constructor|
              type = constructor.synthesize(right).type
              [type, constructor.type_env]
            end

            type_env.join!([right_env, TypeInference::TypeEnv.new(subtyping: checker,
                                                                  const_env: nil)])

            if left_type.is_a?(AST::Types::Boolean)
              typing.add_typing(node, union_type(left_type, right_type), context)
            else
              typing.add_typing(node, union_type(right_type, AST::Builtin.nil_type), context)
            end
          end

        when :or
          yield_self do
            c1, c2 = node.children
            t1 = synthesize(c1, hint: hint).type
            t2 = synthesize(c2, hint: unwrap(t1)).type
            type = union_type(unwrap(t1), t2)
            typing.add_typing(node, type, context)
          end

        when :if
          cond, true_clause, false_clause = node.children
          synthesize(cond).type

          truthy_vars = TypeConstruction.truthy_variables(cond)

          if true_clause
            true_type, true_env = for_branch(true_clause, truthy_vars: truthy_vars).yield_self do |constructor|
              type = constructor.synthesize(true_clause, hint: hint).type
              [type, constructor.type_env]
            end
          end
          if false_clause
            false_type, false_env = for_branch(false_clause).yield_self do |constructor|
              type = constructor.synthesize(false_clause, hint: hint).type
              [type, constructor.type_env]
            end
          end

          type_env.join!([true_env, false_env].compact)
          typing.add_typing(node, union_type(true_type, false_type), context)

        when :case
          yield_self do
            cond, *whens = node.children

            if cond
              cond_type = expand_alias(synthesize(cond).type)
              if cond_type.is_a?(AST::Types::Union)
                var_names = TypeConstruction.value_variables(cond)
                var_types = cond_type.types.dup
              end
            end

            pairs = whens.each.with_object([]) do |clause, pairs|
              if clause&.type == :when
                test_types = clause.children.take(clause.children.size - 1).map do |child|
                  expand_alias(synthesize(child, hint: hint).type)
                end

                if (body = clause.children.last)
                  if var_names && var_types && test_types.all? {|type| type.is_a?(AST::Types::Name::Class)}
                    var_types_in_body = test_types.flat_map {|test_type|
                      filtered_types = var_types.select {|var_type| var_type.is_a?(AST::Types::Name::Base) && var_type.name == test_type.name}
                      if filtered_types.empty?
                        to_instance_type(test_type)
                      else
                        filtered_types
                      end
                    }
                    var_types.reject! {|type|
                      var_types_in_body.any? {|test_type|
                        type.is_a?(AST::Types::Name::Base) && test_type.name == type.name
                      }
                    }

                    type_case_override = var_names.each.with_object({}) do |var_name, hash|
                      hash[var_name] = union_type(*var_types_in_body)
                    end
                  else
                    type_case_override = nil
                  end

                  for_branch(body, type_case_override: type_case_override).yield_self do |body_construction|
                    type = body_construction.synthesize(body, hint: hint).type
                    pairs << [type, body_construction.type_env]
                  end
                else
                  pairs << [AST::Builtin.nil_type, nil]
                end
              else
                if clause
                  if var_types
                    if !var_types.empty?
                      type_case_override = var_names.each.with_object({}) do |var_name, hash|
                        hash[var_name] = union_type(*var_types)
                      end
                      var_types.clear
                    else
                      typing.add_error Errors::ElseOnExhaustiveCase.new(node: node, type: cond_type)
                      type_case_override = var_names.each.with_object({}) do |var_name, hash|
                        hash[var_name] = AST::Builtin.any_type
                      end
                    end
                  end

                  for_branch(clause, type_case_override: type_case_override).yield_self do |body_construction|
                    type = body_construction.synthesize(clause, hint: hint).type
                    pairs << [type, body_construction.type_env]
                  end
                end
              end
            end

            types = pairs.map(&:first)
            envs = pairs.map(&:last)

            unless var_types&.empty? || whens.last
              types.push AST::Builtin.nil_type
            end

            type_env.join!(envs.compact)
            typing.add_typing(node, union_type(*types), context)
          end

        when :rescue
          yield_self do
            body, *resbodies, else_node = node.children
            body_type = synthesize(body).type if body

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
                  when type.is_a?(AST::Types::Name::Class)
                    to_instance_type(type)
                  else
                    AST::Builtin.any_type
                  end
                end
                type_override[var_name] = AST::Types::Union.build(types: instance_types)
              when var_name
                type_override[var_name] = AST::Builtin.any_type
              end

              resbody_construction = for_branch(resbody, type_case_override: type_override)

              type = if body
                       resbody_construction.synthesize(body).type
                     else
                       AST::Builtin.nil_type
                     end
              [type, resbody_construction.type_env]
            end
            resbody_types, resbody_envs = resbody_pairs.transpose

            if else_node
              else_construction = for_branch(else_node)
              else_type = else_construction.synthesize(else_node).type
              else_env = else_construction.type_env
            end

            type_env.join!([*resbody_envs, else_env].compact)

            types = [body_type, *resbody_types, else_type].compact
            typing.add_typing(node, union_type(*types), context)
          end

        when :resbody
          yield_self do
            klasses, asgn, body = node.children
            synthesize(klasses) if klasses
            synthesize(asgn) if asgn
            body_type = synthesize(body).type if body
            typing.add_typing(node, body_type, context)
          end

        when :ensure
          yield_self do
            body, ensure_body = node.children
            body_type = synthesize(body).type if body
            synthesize(ensure_body) if ensure_body
            typing.add_typing(node, union_type(body_type), context)
          end

        when :masgn
          type_masgn(node)

        when :while, :while_post, :until, :until_post
          yield_self do
            cond, body = node.children

            synthesize(cond)
            truthy_vars = node.type == :while ? TypeConstruction.truthy_variables(cond) : Set.new

            if body
              for_loop = for_branch(body,
                                    truthy_vars: truthy_vars,
                                    break_context: TypeInference::Context::BreakContext.new(
                                      break_type: nil,
                                      next_type: nil
                                    ))
              for_loop.synthesize(body)
              type_env.join!([for_loop.type_env])
            end

            typing.add_typing(node, AST::Builtin.any_type, context)
          end

        when :irange, :erange
          types = node.children.map {|n| synthesize(n).type }
          type = AST::Builtin::Range.instance_type(union_type(*types))
          typing.add_typing(node, type, context)

        when :regexp
          each_child_node(node) do |child|
            synthesize(child).type
          end

          typing.add_typing(node, AST::Builtin::Regexp.instance_type, context)

        when :regopt
          # ignore
          typing.add_typing(node, AST::Builtin.any_type, context)

        when :nth_ref, :back_ref
          typing.add_typing(node, AST::Builtin::String.instance_type, context)

        when :or_asgn, :and_asgn
          yield_self do
            _, rhs = node.children
            rhs_type = synthesize(rhs).type
            typing.add_typing(node, rhs_type, context)
          end

        when :defined?
          each_child_node(node) do |child|
            synthesize(child).type
          end

          typing.add_typing(node, AST::Builtin.any_type, context)

        when :gvasgn
          yield_self do
            name, rhs = node.children
            type = type_env.get(gvar: name) do
              fallback_to_any(node)
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

            typing.add_typing(node, type, context)
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
                if method&.overload?
                  return_types = method.types.select {|method_type|
                    method_type.params.each_type.count == 0
                  }.map(&:return_type)

                  unless return_types.empty?
                    type = AST::Types::Proc.new(params: Interface::Params.empty.update(required: [param_type]),
                                                return_type: AST::Types::Union.build(types: return_types))
                  end
                end
              else
                Steep.logger.error "Passing multiple args through Symbol#to_proc is not supported yet"
              end
            end

            type ||= synthesize(node.children[0], hint: hint).type

            typing.add_typing node, type, context
          end

        when :blockarg
          yield_self do
            each_child_node node do |child|
              synthesize(child)
            end

            typing.add_typing node, AST::Builtin.any_type, context
          end

        when :splat, :sclass, :alias
          yield_self do
            Steep.logger.error "Unsupported node #{node.type} (#{node.location.expression.source_buffer.name}:#{node.location.expression.line})"

            each_child_node node do |child|
              synthesize(child)
            end

            typing.add_typing node, AST::Builtin.any_type, context
          end

        else
          raise "Unexpected node: #{node.inspect}, #{node.location.expression}"
        end
      end
    end

    def check(node, type, constraints: Subtyping::Constraints.empty)
      pair = synthesize(node, hint: type)

      result = check_relation(sub_type: pair.type, super_type: type, constraints: constraints)
      if result.failure?
        yield(type, pair.type, result)
      end

      pair
    end

    def type_assignment(var, rhs, node, hint: nil)
      if rhs
        expand_alias(synthesize(rhs, hint: type_env.lvar_types[var.name] || hint).type) do |rhs_type|
          node_type = assign_type_to_variable(var, rhs_type, node)
          typing.add_typing(node, node_type, context)
        end
      else
        raise
        lhs_type = variable_type(var)

        if lhs_type
          typing.add_typing(node, lhs_type, context)
        else
          fallback_to_any node
        end
      end
    end

    def assign_type_to_variable(var, type, node)
      name = var.name
      type_env.assign(lvar: name, type: type, self_type: self_type) do |result|
        var_type = type_env.get(lvar: name)
        typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                            lhs_type: var_type,
                                                            rhs_type: type,
                                                            result: result))
      end
    end

    def type_ivasgn(name, rhs, node)
      rhs_type = synthesize(rhs, hint: type_env.get(ivar: name) { fallback_to_any(node).type }).type
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
      typing.add_typing(node, ivar_type, context)
    end

    def type_masgn(node)
      lhs, rhs = node.children
      rhs_original = synthesize(rhs).type
      rhs_type = expand_alias(rhs_original)

      case
      when rhs.type == :array && lhs.children.all? {|a| a.type == :lvasgn || a.type == :ivasgn} && lhs.children.size == rhs.children.size
        pairs = lhs.children.zip(rhs.children)
        pairs.each do |(l, r)|
          case
          when l.type == :lvasgn
            type_assignment(l.children.first, r, l)
          when l.type == :ivasgn
            type_ivasgn(l.children.first, r, l)
          end
        end

        typing.add_typing(node, rhs_type, context)

      when rhs_type.is_a?(AST::Types::Tuple) && lhs.children.all? {|a| a.type == :lvasgn || a.type == :ivasgn}
        lhs.children.each.with_index do |asgn, index|
          type = rhs_type.types[index]

          case
          when asgn.type == :lvasgn && asgn.children[0].name != :_
            type ||= AST::Builtin.nil_type
            type_env.assign(lvar: asgn.children[0].name, type: type, self_type: self_type) do |result|
              var_type = type_env.get(lvar: asgn.children[0].name)
              typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                  lhs_type: var_type,
                                                                  rhs_type: type,
                                                                  result: result))
            end
          when asgn.type == :ivasgn
            type ||= AST::Builtin.nil_type
            type_env.assign(ivar: asgn.children[0], type: type) do |result|
              var_type = type_env.get(ivar: asgn.children[0])
              typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                  lhs_type: var_type,
                                                                  rhs_type: type,
                                                                  result: result))
            end
          end
        end

        typing.add_typing(node, rhs_type, context)

      when rhs_type.is_a?(AST::Types::Any)
        fallback_to_any(node)

      when AST::Builtin::Array.instance_type?(rhs_type)
        element_type = rhs_type.args.first

        lhs.children.each do |assignment|
          case assignment.type
          when :lvasgn
            assign_type_to_variable(assignment.children.first, element_type, assignment)
          when :ivasgn
            assignment.children.first.yield_self do |ivar|
              type_env.assign(ivar: ivar, type: element_type, self_type: self_type) do |error|
                case error
                when Subtyping::Result::Failure
                  type = type_env.get(ivar: ivar)
                  typing.add_error(Errors::IncompatibleAssignment.new(node: assignment,
                                                                      lhs_type: type,
                                                                      rhs_type: element_type,
                                                                      result: error))
                when nil
                  fallback_to_any node
                end
              end
            end
          end
        end

        typing.add_typing node, rhs_type, context

      when rhs_type.is_a?(AST::Types::Union) &&
        rhs_type.types.all? {|type| AST::Builtin::Array.instance_type?(type)}

        types = rhs_type.types.flat_map do |type|
          type.args.first
        end

        element_type = AST::Types::Union.build(types: types)

        lhs.children.each do |assignment|
          case assignment.type
          when :lvasgn
            assign_type_to_variable(assignment.children.first, element_type, assignment)
          when :ivasgn
            assignment.children.first.yield_self do |ivar|
              type_env.assign(ivar: ivar, type: element_type) do |error|
                case error
                when Subtyping::Result::Failure
                  type = type_env.get(ivar: ivar)
                  typing.add_error(Errors::IncompatibleAssignment.new(node: assignment,
                                                                      lhs_type: type,
                                                                      rhs_type: element_type,
                                                                      result: error))
                when nil
                  fallback_to_any node
                end
              end
            end
          end
        end

        typing.add_typing node, rhs_type, context

      else
        Steep.logger.error("Unsupported masgn: #{rhs.type} (#{rhs_type})")
        fallback_to_any(node)
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

      block_type = type_block(block_param_hint: params_hint,
                              block_type_hint: return_hint,
                              node_type_hint: nil,
                              block_params: params,
                              block_body: block_body,
                              block_annotations: block_annotations,
                              topdown_hint: true)

      typing.add_typing node, block_type, context
    end

    def type_send(node, send_node:, block_params:, block_body:, unwrap: false)
      receiver, method_name, *arguments = send_node.children
      receiver_type = receiver ? synthesize(receiver).type : AST::Types::Self.new

      if unwrap
        receiver_type = unwrap(receiver_type)
      end

      receiver_type = expand_alias(receiver_type)

      return_type = case receiver_type
                    when AST::Types::Any
                      typing.add_typing node, AST::Builtin.any_type, context

                    when nil
                      fallback_to_any node

                    when AST::Types::Void, AST::Types::Bot, AST::Types::Top
                      fallback_to_any node do
                        Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
                      end

                    else
                      case expanded_receiver_type = expand_self(receiver_type)
                      when AST::Types::Self
                        Steep.logger.error "`self` type cannot be resolved to concrete type"
                        fallback_to_any node do
                          Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
                        end
                      else
                        begin
                          interface = checker.factory.interface(receiver_type,
                                                                private: !receiver,
                                                                self_type: expanded_receiver_type)

                          method = interface.methods[method_name]

                          if method
                            args = TypeInference::SendArgs.from_nodes(arguments)
                            return_type, _ = type_method_call(node,
                                                              method: method,
                                                              method_name: method_name,
                                                              args: args,
                                                              block_params: block_params,
                                                              block_body: block_body,
                                                              receiver_type: receiver_type,
                                                              topdown_hint: true)

                            typing.add_typing node, return_type, context
                          else
                            fallback_to_any node do
                              Errors::NoMethod.new(node: node, method: method_name, type: expanded_receiver_type)
                            end
                          end
                        rescue => exn
                          $stderr.puts exn.inspect
                          exn.backtrace.each do |t|
                            $stderr.puts t
                          end

                          fallback_to_any node do
                            Errors::NoMethod.new(node: node, method: method_name, type: expanded_receiver_type)
                          end
                        end
                      end
                    end

      case return_type
      when nil, Errors::Base
        arguments.each do |arg|
          unless typing.has_type?(arg)
            if arg.type == :splat
              type = synthesize(arg.children[0]).type
              typing.add_typing(arg, AST::Builtin::Array.instance_type(type), context)
            else
              synthesize(arg)
            end
          end
        end

        if block_body && block_params
          unless typing.has_type?(block_body)
            block_annotations = source.annotations(block: node, builder: checker.builder, current_module: current_namespace)
            params = TypeInference::BlockParams.from_node(block_params, annotations: block_annotations)
            pairs = params.each.map {|param| [param, AST::Builtin.any_type]}

            for_block, _ = for_block(block_annotations: block_annotations,
                                     param_pairs: pairs,
                                     method_return_type: AST::Builtin.any_type,
                                     typing: typing)

            for_block.synthesize(block_body)
          end
        end
      else
        return_type
      end
    end

    def for_block(block_annotations:, param_pairs:, method_return_type:, typing:)
      block_type_env = type_env.dup.yield_self do |env|
        param_pairs.each do |param, type|
          if param.type
            env.set(lvar: param.var.name, type: param.type)
          else
            env.set(lvar: param.var.name, type: type)
          end
        end

        env.with_annotations(
          lvar_types: block_annotations.lvar_types,
          ivar_types: block_annotations.ivar_types,
          const_types: block_annotations.const_types,
        )
      end

      return_type = if block_annotations.break_type
                      union_type(method_return_type, block_annotations.break_type)
                    else
                      method_return_type
                    end
      Steep.logger.debug("return_type = #{return_type}")

      block_context = TypeInference::Context::BlockContext.new(body_type: block_annotations.block_type)
      Steep.logger.debug("block_context { body_type: #{block_context.body_type} }")

      break_context = TypeInference::Context::BreakContext.new(
        break_type: block_annotations.break_type || method_return_type,
        next_type: block_annotations.block_type
      )
      Steep.logger.debug("break_context { type: #{break_context.break_type} }")

      [self.class.new(
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
          type_env: block_type_env
        )
      ), return_type]
    end

    def expand_self(type)
      if type.is_a?(AST::Types::Self) && self_type
        self_type
      else
        type
      end
    end

    def type_method_call(node, method_name:, receiver_type:, method:, args:, block_params:, block_body:, topdown_hint:)
      case
      when method.union?
        yield_self do
          results = method.types.map do |method|
            typing.new_child do |child_typing|
              type, error = with_new_typing(child_typing).type_method_call(node,
                                                                           method_name: method_name,
                                                                           receiver_type: receiver_type,
                                                                           method: method,
                                                                           args: args,
                                                                           block_params: block_params,
                                                                           block_body: block_body,
                                                                           topdown_hint: false)
              [
                type,
                child_typing,
                error
              ]
            end
          end

          if (type, typing, error = results.find {|_, _, error| error })
            typing.save!
            [type, error]
          else
            _, typing, _ = results.first
            typing.save!

            [union_type(*results.map(&:first)), nil]
          end
        end

      when method.intersection?
        yield_self do
          results = method.types.map do |method|
            typing.new_child do |child_typing|
              type, error = with_new_typing(child_typing).type_method_call(node,
                                                                           method_name: method_name,
                                                                           receiver_type: receiver_type,
                                                                           method: method,
                                                                           args: args,
                                                                           block_params: block_params,
                                                                           block_body: block_body,
                                                                           topdown_hint: false)
              [
                type,
                child_typing,
                error
              ]
            end
          end

          successes = results.select {|_, _, error| !error }
          unless successes.empty?
            types = successes.map {|type, typing, _| type }
            typing = successes[0][1]
            typing.save!

            [AST::Types::Intersection.build(types: types), nil]
          else
            type, typing, error = results.first
            typing.save!

            [type, error]
          end
        end

      when method.overload?
        yield_self do
          results = method.types.flat_map do |method_type|
            Steep.logger.tagged method_type.to_s do
              case method_type
              when Interface::MethodType
                zips = args.zips(method_type.params, method_type.block&.type)

                zips.map do |arg_pairs|
                  typing.new_child do |child_typing|
                    result = self.with_new_typing(child_typing).try_method_type(
                      node,
                      receiver_type: receiver_type,
                      method_type: method_type,
                      args: args,
                      arg_pairs: arg_pairs,
                      block_params: block_params,
                      block_body: block_body,
                      child_typing: child_typing,
                      topdown_hint: topdown_hint
                    )

                    [result, child_typing, method_type]
                  end
                end
              when :any
                typing.new_child do |child_typing|
                  this = self.with_new_typing(child_typing)

                  args.args.each do |arg|
                    this.synthesize(arg)
                  end

                  if block_body
                    this.synthesize(block_body)
                  end

                  child_typing.add_typing node, AST::Builtin.any_type, context

                  [[AST::Builtin.any_type, child_typing, :any]]
                end
              end
            end
          end

          unless results.empty?
            result, call_typing, method_type = results.find {|result, _, _| !result.is_a?(Errors::Base) } || results.last
          else
            method_type = method.types.last
            result = Errors::IncompatibleArguments.new(node: node, receiver_type: receiver_type, method_type: method_type)
            call_typing = typing.new_child
          end
          call_typing.save!

          case result
          when Errors::Base
            if method.types.size == 1
              typing.add_error result
              type = case method_type.return_type
                     when AST::Types::Var
                       AST::Builtin.any_type
                     else
                       method_type.return_type
                     end
            else
              typing.add_error Errors::UnresolvedOverloading.new(node: node,
                                                                 receiver_type: expand_self(receiver_type),
                                                                 method_name: method_name,
                                                                 method_types: method.types)
              type = AST::Builtin.any_type
            end

            [type, result]
          else # Type
            [result, nil]
          end
        end
      end
    end

    def check_keyword_arg(receiver_type:, node:, method_type:, constraints:)
      params = method_type.params

      case node.type
      when :hash
        keyword_hash_type = AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type,
                                                             AST::Builtin.any_type)
        typing.add_typing node, keyword_hash_type, context

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

              typing.add_typing key_node, AST::Builtin::Symbol.instance_type, context

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
            AST::Types::Union.build(types: value_types,
                                    location: method_type.location)
          )
        else
          hash_elements = params.required_keywords.merge(
            method_type.params.optional_keywords.transform_values do |type|
              AST::Types::Union.build(types: [type, AST::Builtin.nil_type],
                                      location: method_type.location)
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

    def try_method_type(node, receiver_type:, method_type:, args:, arg_pairs:, block_params:, block_body:, child_typing:, topdown_hint:)
      fresh_types = method_type.type_params.map {|x| AST::Types::Var.fresh(x)}
      fresh_vars = Set.new(fresh_types.map(&:name))
      instantiation = Interface::Substitution.build(method_type.type_params, fresh_types)

      construction = self.class.new(
        checker: checker,
        source: source,
        annotations: annotations,
        typing: child_typing,
        context: context
      )

      method_type.instantiate(instantiation).yield_self do |method_type|
        constraints = Subtyping::Constraints.new(unknowns: fresh_types.map(&:name))
        variance = Subtyping::VariableVariance.from_method_type(method_type)
        occurence = Subtyping::VariableOccurence.from_method_type(method_type)

        arg_pairs.each do |pair|
          case pair
          when Array
            (arg_node, param_type) = pair

            param_type = param_type.subst(instantiation)

            arg_type = if arg_node.type == :splat
                         type = construction.synthesize(arg_node.children[0]).type
                         child_typing.add_typing(arg_node, type, context).type
                       else
                         construction.synthesize(arg_node, hint: topdown_hint ? param_type : nil).type
                       end

            check_relation(sub_type: arg_type, super_type: param_type, constraints: constraints).else do |result|
              return Errors::ArgumentTypeMismatch.new(
                node: arg_node,
                receiver_type: receiver_type,
                expected: param_type,
                actual: arg_type
              )
            end
          else
            # keyword
            result = check_keyword_arg(receiver_type: receiver_type,
                                       node: pair,
                                       method_type: method_type,
                                       constraints: constraints)

            if result.is_a?(Errors::Base)
              return result
            end
          end
        end

        if block_params && method_type.block
          block_annotations = source.annotations(block: node, factory: checker.factory, current_module: current_namespace)
          block_params_ = TypeInference::BlockParams.from_node(block_params, annotations: block_annotations)
          block_param_hint = block_params_.params_type(
            hint: topdown_hint ? method_type.block.type.params : nil
          )

          check_relation(sub_type: AST::Types::Proc.new(params: block_param_hint, return_type: AST::Types::Any.new),
                         super_type: method_type.block.type,
                         constraints: constraints).else do |result|
            return Errors::IncompatibleBlockParameters.new(
              node: node,
              method_type: method_type
            )
          end
        end

        case
        when method_type.block && block_params
          Steep.logger.debug "block is okay: method_type=#{method_type}"
          Steep.logger.debug "Constraints = #{constraints}"

          begin
            method_type.subst(constraints.solution(checker, self_type: self_type, variance: variance, variables: occurence.params)).yield_self do |method_type|
              block_type = construction.type_block(block_param_hint: method_type.block.type.params,
                                                   block_type_hint: method_type.block.type.return_type,
                                                   node_type_hint: method_type.return_type,
                                                   block_params: block_params_,
                                                   block_body: block_body,
                                                   block_annotations: block_annotations,
                                                   topdown_hint: topdown_hint)

              result = check_relation(sub_type: block_type.return_type,
                                      super_type: method_type.block.type.return_type,
                                      constraints: constraints)

              case result
              when Subtyping::Result::Success
                method_type.return_type.subst(constraints.solution(checker, self_type: self_type, variance: variance, variables: fresh_vars)).yield_self do |ret_type|
                  if block_annotations.break_type
                    AST::Types::Union.new(types: [block_annotations.break_type, ret_type])
                  else
                    ret_type
                  end
                end

              when Subtyping::Result::Failure
                Errors::BlockTypeMismatch.new(node: node,
                                              expected: method_type.block.type,
                                              actual: block_type,
                                              result: result)
              end
            end

          rescue Subtyping::Constraints::UnsatisfiableConstraint => exn
            Errors::UnsatisfiableConstraint.new(node: node,
                                                method_type: method_type,
                                                var: exn.var,
                                                sub_type: exn.sub_type,
                                                super_type: exn.super_type,
                                                result: exn.result)
          end

        when method_type.block && args.block_pass_arg
          begin
            method_type.subst(constraints.solution(checker, self_type: self_type, variance: variance, variables: occurence.params)).yield_self do |method_type|
              block_type = synthesize(args.block_pass_arg,
                                      hint: topdown_hint ? method_type.block.type : nil).type
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

              case result
              when Subtyping::Result::Success
                method_type.return_type.subst(constraints.solution(checker, self_type: self_type, variance: variance, variables: fresh_vars))

              when Subtyping::Result::Failure
                Errors::BlockTypeMismatch.new(node: node,
                                              expected: method_type.block.type,
                                              actual: block_type,
                                              result: result)
              end
            end

          rescue Subtyping::Constraints::UnsatisfiableConstraint => exn
            Errors::UnsatisfiableConstraint.new(node: node,
                                                method_type: method_type,
                                                var: exn.var,
                                                sub_type: exn.sub_type,
                                                super_type: exn.super_type,
                                                result: exn.result)
          end

        when (!method_type.block || method_type.block.optional?) && !block_params && !block_body && !args.block_pass_arg
          # OK, without block
          method_type.subst(constraints.solution(checker, variance: variance, variables: fresh_vars, self_type: self_type)).return_type

        when !method_type.block && (block_params || args.block_pass_arg)
          Errors::UnexpectedBlockGiven.new(
            node: node,
            method_type: method_type
          )

        when method_type.block && !method_type.block.optional? && !block_params && !block_body && !args.block_pass_arg
          Errors::RequiredBlockMissing.new(
            node: node,
            method_type: method_type
          )

        else
          raise "Unexpected case condition"
        end
      end
    end

    def type_block(block_param_hint:, block_type_hint:, node_type_hint:, block_params:, block_body:, block_annotations:, topdown_hint:)
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

      block_type_env = type_env.dup.tap do |env|
        param_types_hash.each do |name, type|
          env.set(lvar: name, type: type)
        end

        block_annotations.lvar_types.each do |name, type|
          env.set(lvar: name, type: type)
        end
      end

      break_type = if block_annotations.break_type
                     union_type(node_type_hint, block_annotations.break_type)
                   else
                     node_type_hint
                   end
      Steep.logger.debug("return_type = #{break_type}")

      block_context = TypeInference::Context::BlockContext.new(body_type: block_annotations.block_type)
      Steep.logger.debug("block_context { body_type: #{block_context.body_type} }")

      break_context = TypeInference::Context::BreakContext.new(
        break_type: break_type,
        next_type: block_context.body_type
      )
      Steep.logger.debug("break_context { type: #{break_context.break_type} }")

      for_block_body = self.class.new(
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
          type_env: block_type_env
        )
      )

      if block_body
        return_type = if (body_type = block_context.body_type)
                        for_block_body.check(block_body, body_type) do |expected, actual, result|
                          typing.add_error Errors::BlockTypeMismatch.new(node: block_body,
                                                                         expected: expected,
                                                                         actual: actual,
                                                                         result: result)

                        end
                        body_type
                      else
                        for_block_body.synthesize(block_body, hint: topdown_hint ? block_type_hint : nil).type
                      end
      else
        return_type = AST::Builtin.any_type
      end

      AST::Types::Proc.new(
        params: block_param_hint || block_params.params_type,
        return_type: return_type
      ).tap do |type|
        Steep.logger.debug "block_type == #{type}"
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
      if module_name.relative? && module_name.namespace.empty?
        current_namespace.append(module_name.name)
      else
        current_namespace
      end
    end

    def absolute_name(module_name)
      if current_namespace
        module_name.in_namespace(current_namespace)
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
      AST::Types::Union.build(types: types)
    end

    def validate_method_definitions(node, module_name)
      expected_instance_method_names = (module_context.instance_definition&.methods || {}).each.with_object(Set[]) do |(name, method), set|
        if method.implemented_in == module_context.instance_definition.declaration
          set << name
        end
      end
      expected_module_method_names = (module_context.module_definition&.methods || {}).each.with_object(Set[]) do |(name, method), set|
        if method.implemented_in == module_context.module_definition.declaration
          set << name
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

      typing.add_typing node, AST::Builtin.any_type, context
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

    def self.truthy_variables(node)
      case node&.type
      when :lvar
        Set.new([node.children.first.name])
      when :lvasgn
        Set.new([node.children.first.name]) + truthy_variables(node.children[1])
      when :and
        truthy_variables(node.children[0]) + truthy_variables(node.children[1])
      when :begin
        truthy_variables(node.children.last)
      else
        Set.new()
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

    def deep_expand_alias(type, recursive: Set.new, &block)
      raise "Recursive type definition: #{type}" if recursive.member?(type)

      ty = case type
           when AST::Types::Name::Alias
             deep_expand_alias(expand_alias(type), recursive: recursive << type)
           else
             type
           end

      if block_given?
        yield ty
      else
        ty
      end
    end

    def expand_alias(type, &block)
      checker.factory.expand_alias(type, &block)
    end

    def test_literal_type(literal, hint)
      case hint
      when AST::Types::Literal
        if hint.value == literal
          hint
        end
      when AST::Types::Union
        if hint.types.any? {|ty| ty.is_a?(AST::Types::Literal) && ty.value == literal}
          hint
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
                     when AST::Types::Name::Class, AST::Types::Name::Module
                       checker.factory.env.find_class(checker.factory.type_name_1(type.name)).type_params.each.map { AST::Builtin.any_type }
                     else
                       raise "unexpected type to to_instance_type: #{type}"
                     end

      AST::Types::Name::Instance.new(name: type.name, args: args)
    end

    def try_hash_type(node, hint)
      case hint
      when AST::Types::Record
        typing.new_child do |child_typing|
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
          typing.add_typing(node, hash, context)
        end
      when AST::Types::Union
        hint.types.find do |type|
          try_hash_type(node, type)
        end
      end
    end
  end
end
