module Steep
  class TypeConstruction
    module Types
      module_function

      def any
        AST::Types::Any.new
      end

      def symbol_instance
        AST::Types::Name.new_instance(name: "::Symbol")
      end

      def nil_instance
        AST::Types::Name.new_instance(name: "::NilClass")
      end

      def string_instance
        AST::Types::Name.new_instance(name: "::String")
      end

      def array_instance(type)
        AST::Types::Name.new_instance(name: "::Array", args: [type])
      end
    end

    class MethodContext
      attr_reader :name
      attr_reader :method
      attr_reader :constructor

      def initialize(name:, method:, method_type:, return_type:, constructor:)
        @name = name
        @method = method
        @return_type = return_type
        @method_type = method_type
        @constructor = constructor
      end

      def return_type
        @return_type || method_type&.return_type
      end

      def block_type
        method_type&.block
      end

      def method_type
        @method_type || method&.types&.first
      end

      def super_method
        method&.super_method
      end
    end

    class BlockContext
      attr_reader :break_type
      attr_reader :body_type

      def initialize(break_type:, body_type:)
        @break_type = break_type
        @body_type = body_type
      end
    end

    class ModuleContext
      attr_reader :instance_type
      attr_reader :module_type
      attr_reader :defined_instance_methods
      attr_reader :defined_module_methods
      attr_reader :const_types
      attr_reader :implement_name

      def initialize(instance_type:, module_type:, const_types:, implement_name:)
        @instance_type = instance_type
        @module_type = module_type
        @defined_instance_methods = Set.new
        @defined_module_methods = Set.new
        @const_types = const_types
        @implement_name = implement_name
      end
    end

    attr_reader :checker
    attr_reader :source
    attr_reader :annotations
    attr_reader :var_types
    attr_reader :ivar_types
    attr_reader :typing
    attr_reader :method_context
    attr_reader :block_context
    attr_reader :module_context
    attr_reader :self_type

    def initialize(checker:, source:, annotations:, var_types:, ivar_types: {}, typing:, self_type:, method_context:, block_context:, module_context:)
      @checker = checker
      @source = source
      @annotations = annotations
      @var_types = var_types
      @ivar_types = ivar_types
      @typing = typing
      @self_type = self_type
      @block_context = block_context
      @method_context = method_context
      @module_context = module_context
    end

    def method_entry(method_name, receiver_type:)
      method = nil

      if receiver_type
        interface = checker.resolve(receiver_type)
        method = interface.methods[method_name]
      end

      if (type = annotations.lookup_method_type(method_name))
        Interface::Method.new(type_name: nil,
                              name: method_name,
                              types: [checker.builder.method_type_to_method_type(type, current: nil)],
                              super_method: method,
                              attributes: [])
      else
        method
      end
    end

    def for_new_method(method_name, node, args:, self_type:)
      annots = source.annotations(block: node)
      self_type = annots.self_type || self_type

      method = method_entry(method_name, receiver_type: self_type)
      method_type = method&.types&.first
      if method_type
        var_types = TypeConstruction.parameter_types(args, method_type).transform_values {|type| absolute_type(type) }
        unless TypeConstruction.valid_parameter_env?(var_types, args, method_type.params)
          typing.add_error Errors::MethodParameterTypeMismatch.new(node: node)
        end
      else
        var_types = {}
      end

      constructor_method = method&.attributes&.include?(:constructor)

      method_context = MethodContext.new(
        name: method_name,
        method: method,
        method_type: method_type,
        return_type: annots.return_type,
        constructor: constructor_method
      )

      ivar_types = annots.ivar_types.keys.each.with_object({}) do |var, env|
        env[var] = annots.ivar_types[var]
      end

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        var_types: var_types,
        block_context: nil,
        self_type: self_type,
        method_context: method_context,
        typing: typing,
        module_context: module_context,
        ivar_types: ivar_types
      )
    end

    def for_module(node)
      annots = source.annotations(block: node)

      module_type = AST::Types::Name.new_instance(name: "::Module")

      if annots.implement_module
        module_name = annots.implement_module.name.name
        module_args = annots.implement_module.name.args.map {|x| AST::Types::Var.new(name: x) }

        abstract = checker.builder.build(TypeName::Instance.new(name: module_name))

        instance_type = absolute_type(
          AST::Types::Name.new_instance(name: module_name, args: module_args)
        )

        unless abstract.supers.empty?
          instance_type = AST::Types::Intersection.new(
            types: [instance_type, AST::Types::Name.new_instance(name: "::Object")] + abstract.supers.map {|x| absolute_type(x) }
          )
        end

        module_type = AST::Types::Intersection.new(types: [
          AST::Types::Name.new_instance(name: "::Module"),
          absolute_type(AST::Types::Name.new_module(name: module_name, args: module_args))
        ])
      end

      if annots.instance_type
        instance_type = absolute_type(annots.instance_type)
      end

      if annots.module_type
        module_type = absolute_type(annots.module_type)
      end

      module_context_ = ModuleContext.new(
        instance_type: instance_type,
        module_type: module_type,
        const_types: annots.const_types,
        implement_name: annots.implement_module&.name
      )

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        var_types: {},
        typing: typing,
        method_context: nil,
        block_context: nil,
        module_context: module_context_,
        self_type: module_context_.module_type
      )
    end

    def for_class(node)
      annots = source.annotations(block: node)

      if annots.implement_module
        class_name = annots.implement_module.name.name
        class_args = annots.implement_module.name.args.map {|x| AST::Types::Var.new(name: x) }

        _ = checker.builder.build(TypeName::Instance.new(name: class_name))

        instance_type = AST::Types::Name.new_instance(name: class_name, args: class_args)
        module_type = AST::Types::Name.new_class(name: class_name, args: class_args, constructor: nil)
      end

      module_context = ModuleContext.new(
        instance_type: annots.instance_type || instance_type,
        module_type: annots.module_type || module_type,
        const_types: annots.const_types,
        implement_name: annots.implement_module&.name
      )

      self.class.new(
        checker: checker,
        source: source,
        annotations: annots,
        var_types: {},
        typing: typing,
        method_context: nil,
        block_context: nil,
        module_context: module_context,
        self_type: module_context.module_type
      )
    end

    def synthesize(node)
      Steep.logger.tagged "synthesize:(#{node.location.expression.to_s.split(/:/, 2).last})" do
        Steep.logger.debug node.type
        case node.type
        when :begin
          yield_self do
            type = each_child_node(node).map do |child|
              synthesize(child)
            end.last

            typing.add_typing(node, type)
          end

        when :lvasgn
          yield_self do
            var = node.children[0]
            rhs = node.children[1]

            type_assignment(var, rhs, node)
          end

        when :lvar
          yield_self do
            var = node.children[0]

            if (type = variable_type(var))
              typing.add_typing(node, type)
            else
              fallback_to_any node
              typing.add_var_type var, Types.any
            end
          end

        when :ivasgn
          name = node.children[0]
          value = node.children[1]

          if (type = ivar_types[name])
            check(value, type) do |_, value_type, result|
              typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                  lhs_type: type,
                                                                  rhs_type: value_type,
                                                                  result: result))
            end
            typing.add_typing(node, type)
          else
            value_type = synthesize(value)
            typing.add_typing(node, value_type)
          end

        when :ivar
          type = ivar_types[node.children[0]]
          if type
            typing.add_typing(node, type)
          else
            fallback_to_any node
          end

        when :send
          yield_self do
            if self_class?(node)
              module_type = module_context.module_type
              type = if module_type.is_a?(AST::Types::Name)
                       AST::Types::Name.new(name: module_type.name.updated(constructor: method_context.constructor),
                                            args: module_type.args)
                     else
                       module_type
                     end
              typing.add_typing(node, type)
            else
              type_send(node, send_node: node, block_params: nil, block_body: nil)
            end
          end

        when :super
          yield_self do
            if self_type && method_context&.method
              if method_context.super_method
                each_child_node(node) do |child| synthesize(child) end

                super_method = method_context.super_method
                args = TypeInference::SendArgs.from_nodes(node.children.dup)

                return_type_or_error = type_method_call(node, method: super_method, args: args, block_params: nil, block_body: nil)

                if return_type_or_error.is_a?(Errors::Base)
                  fallback_to_any node do
                    return_type_or_error
                  end
                else
                  typing.add_typing node, return_type_or_error
                end
              else
                fallback_to_any node do
                  Errors::UnexpectedSuper.new(node: node, method: method_context.name)
                end
              end
            else
              typing.add_typing node, Types.any
            end
          end

        when :block
          yield_self do
            send_node, params, body = node.children
            type_send(node, send_node: send_node, block_params: params, block_body: body)
          end

        when :def
          new = for_new_method(node.children[0],
                               node,
                               args: node.children[1].children,
                               self_type: module_context&.instance_type)

          each_child_node(node.children[1]) do |arg|
            new.synthesize(arg)
          end

          if node.children[2]
            return_type = new.method_context&.return_type
            if return_type
              new.check(node.children[2], return_type) do |_, actual_type, result|
                typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                    expected: return_type,
                                                                    actual: actual_type,
                                                                    result: result))
              end
            else
              new.synthesize(node.children[2])
            end
          end

          if module_context
            module_context.defined_instance_methods << node.children[0]
          end

          typing.add_typing(node, Types.any)

        when :defs
          synthesize(node.children[0]).tap do |self_type|
            new = for_new_method(node.children[1],
                                 node,
                                 args: node.children[2].children,
                                 self_type: self_type)

            each_child_node(node.children[2]) do |arg|
              new.synthesize(arg)
            end

            if node.children[3]
              if new&.method_context&.method_type
                new.check(node.children[3], new.method_context.method_type.return_type) do |return_type, actual_type, result|
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

          typing.add_typing(node, Types.symbol_instance)

        when :return
          value = node.children[0]

          if value
            if method_context&.return_type
              check(value, method_context.return_type) do |_, actual_type, result|
                typing.add_error(Errors::ReturnTypeMismatch.new(node: node,
                                                                expected: method_context.return_type,
                                                                actual: actual_type,
                                                                result: result))
              end
            else
              synthesize(value)
            end
          end

          typing.add_typing(node, Types.any)

        when :break
          value = node.children[0]

          if value
            if block_context&.break_type
              check(value, block_context.break_type) do |break_type, actual_type, result|
                typing.add_error Errors::BreakTypeMismatch.new(node: node,
                                                               expected: break_type,
                                                               actual: actual_type,
                                                               result: result)
              end
            else
              synthesize(value)
            end
          end

          typing.add_typing(node, Types.any)

        when :arg, :kwarg, :procarg0
          var = node.children[0]
          if (type = variable_type(var))
            typing.add_var_type(var, type)
          else
            fallback_to_any node
          end

        when :optarg, :kwoptarg
          var = node.children[0]
          rhs = node.children[1]
          type_assignment(var, rhs, node)

        when :int
          typing.add_typing(node, AST::Types::Name.new_instance(name: "::Integer"))

        when :nil
          typing.add_typing(node, Types.any)

        when :sym
          typing.add_typing(node, Types.symbol_instance)

        when :str
          typing.add_typing(node, Types.string_instance)

        when :true, :false
          typing.add_typing(node, AST::Types::Name.new_interface(name: :_Boolean))

        when :hash
          each_child_node(node) do |pair|
            raise "Unexpected non pair: #{pair.inspect}" unless pair.type == :pair
            each_child_node(pair) do |e|
              synthesize(e)
            end
          end

          typing.add_typing(node, Types.any)

        when :dstr
          each_child_node(node) do |child|
            synthesize(child)
          end

          typing.add_typing(node, Types.string_instance)

        when :dsym
          each_child_node(node) do |child|
            synthesize(child)
          end

          typing.add_typing(node, Types.symbol_instance)

        when :class
          yield_self do
            for_class(node).tap do |constructor|
              constructor.synthesize(node.children[2]) if node.children[2]

              if constructor.module_context&.implement_name
                constructor.validate_method_definitions(node, constructor.module_context.implement_name)
              end
            end

            typing.add_typing(node, Types.nil_instance)
          end

        when :module
          yield_self do
            for_module(node).yield_self do |constructor|
              constructor.synthesize(node.children[1]) if node.children[1]

              if constructor.module_context&.implement_name
                constructor.validate_method_definitions(node, constructor.module_context.implement_name)
              end
            end

            typing.add_typing(node, Types.nil_instance)
          end

        when :self
          if self_type
            typing.add_typing(node, self_type)
          else
            fallback_to_any node
          end

        when :const
          const_name = flatten_const_name(node)
          if const_name
            type = absolute_type((module_context&.const_types || {})[const_name])
          end

          if type
            typing.add_typing(node, type)
          else
            fallback_to_any node
          end

        when :casgn
          yield_self do
            const_name = flatten_const_name(node)
            if const_name
              const_type = absolute_type((module_context&.const_types || {}))[const_name]
            end

            if const_type
              check(node.children.last, const_type) do |_, rhs_type, result|
                typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                    lhs_type: const_type,
                                                                    rhs_type: rhs_type,
                                                                    result: result))
              end
            else
              if module_context.const_types
                module_context.const_types[const_name] = const_type
              end
            end

            typing.add_typing(node, const_type)
          end

        when :yield
          if method_context&.method_type
            if method_context.block_type
              block_type = method_context.block_type
              block_type.params.flat_unnamed_params.map(&:last).zip(node.children).each do |(type, node)|
                if node && type
                  check(node, type) do |_, rhs_type, result|
                    typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                        lhs_type: type,
                                                                        rhs_type: rhs_type,
                                                                        result: result))
                  end
                end
              end

              typing.add_typing(node, block_type.return_type)
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
                types = method_context.super_method.types.map(&:return_type)
                typing.add_typing(node, union_type(*types))
              else
                typing.add_error(Errors::UnexpectedSuper.new(node: node, method: method_context.name))
                fallback_to_any node
              end
            else
              fallback_to_any node
            end
          end

        when :array
          if node.children.empty?
            typing.add_typing(node, Types.array_instance(Types.any))
          else
            types = node.children.map {|e| synthesize(e) }

            if types.uniq.size == 1
              typing.add_typing(node, Types.array_instance(types.first))
            else
              typing.add_typing(node, Types.array_instance(Types.any))
            end
          end

        when :and
          types = each_child_node(node).map {|child| synthesize(child) }
          typing.add_typing(node, types.last)

        when :or
          types = each_child_node(node).map {|child| synthesize(child) }
          type = union_type(*types)
          typing.add_typing(node, type)

        when :if
          cond, true_clause, false_clause = node.children
          synthesize cond
          true_type = synthesize(true_clause) if true_clause
          false_type = synthesize(false_clause) if false_clause

          typing.add_typing(node, union_type(true_type, false_type))

        when :case
          cond, *whens = node.children

          synthesize cond if cond

          types = whens.map do |clause|
            if clause&.type == :when
              clause.children.take(clause.children.size - 1).map do |child|
                synthesize(child)
              end

              if (body = clause.children.last)
                synthesize body
              else
                fallback_to_any body
              end
            else
              synthesize clause if clause
            end
          end

          typing.add_typing(node, union_type(*types))

        else
          raise "Unexpected node: #{node.inspect}, #{node.location.expression}"
        end
      end
    end

    def check(node, type)
      type_ = synthesize(node)

      result = checker.check(
        Subtyping::Relation.new(sub_type: type_,
                                super_type: type),
        constraints: Subtyping::Constraints.empty
      )
      if result.failure?
        yield(type, type_, result)
      end
    end

    def type_assignment(var, rhs, node)
      lhs_type = variable_type(var)

      if rhs
        if lhs_type
          check(rhs, lhs_type) do |_, rhs_type, result|
            typing.add_error(Errors::IncompatibleAssignment.new(node: node,
                                                                lhs_type: lhs_type,
                                                                rhs_type: rhs_type,
                                                                result: result))
          end
          typing.add_var_type(var, lhs_type)
          typing.add_typing(node, lhs_type)
          var_types[var] = lhs_type
          lhs_type
        else
          rhs_type = synthesize(rhs)
          typing.add_var_type(var, rhs_type)
          typing.add_typing(node, rhs_type)
          var_types[var] = rhs_type
          rhs_type
        end
      else
        if lhs_type
          typing.add_var_type(var, lhs_type)
          typing.add_typing(node, lhs_type)
          var_types[var] = lhs_type
        else
          typing.add_var_type(var, Types.any)
          fallback_to_any node
          var_types[var] = Types.any
        end
      end
    end

    def type_send(node, send_node:, block_params:, block_body:)
      receiver, method_name, *arguments = send_node.children
      receiver_type = receiver ? synthesize(receiver) : self_type
      arguments.each {|arg| synthesize(arg) }

      case receiver_type
      when AST::Types::Any
        typing.add_typing node, Types.any

      when nil
        fallback_to_any node

      else
        interface = checker.resolve(receiver_type)
        method = interface.methods[method_name]

        if method
          args = TypeInference::SendArgs.from_nodes(arguments)
          return_type_or_error = type_method_call(node,
                                         method: method,
                                         args: args,
                                         block_params: block_params,
                                         block_body: block_body)

          if return_type_or_error.is_a?(Errors::Base)
            fallback_to_any node do
              return_type_or_error
            end
          else
            typing.add_typing node, return_type_or_error
          end
        else
          fallback_to_any node do
            Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
          end
        end
      end
    end

    def type_method_call(node, method:, args:, block_params:, block_body:)
      results = method.types.map do |method_type|
        Steep.logger.tagged method_type.location.source do
          arg_pairs = args.zip(method_type.params)

          if arg_pairs
            try_method_type(node,
                            method_type: method_type,
                            arg_pairs: arg_pairs,
                            block_params: block_params,
                            block_body: block_body)
          else
            Errors::IncompatibleArguments.new(node: node, method_type: method_type)
          end
        end
      end

      if results.all? {|result| result.is_a?(Errors::Base) }
        results.first
      else
        results.find do |result|
          !result.is_a?(Errors::Base)
        end
      end
    end

    def try_method_type(node, method_type:, arg_pairs:, block_params:, block_body:)
      fresh_types = method_type.type_params.map {|x| AST::Types::Var.fresh(x) }
      instantiation = Interface::Substitution.build(method_type.type_params, fresh_types)

      method_type.instantiate(instantiation).yield_self do |method_type|
        constraints = Subtyping::Constraints.new(domain: fresh_types.map(&:name))

        arg_pairs.each do |(arg_node, param_type)|
          relation = Subtyping::Relation.new(
            sub_type: typing.type_of(node: arg_node),
            super_type: param_type.subst(instantiation)
          )

          checker.check(relation, constraints: constraints).else do |result|
            return Errors::ArgumentTypeMismatch.new(
              node: arg_node,
              expected: relation.super_type,
              actual: relation.sub_type
            )
          end
        end

        method_type.subst(constraints.subst(checker)).yield_self do |method_type|
          case
          when method_type.block && block_params
            annots = source.annotations(block: node)

            params = TypeInference::BlockParams.from_node(block_params, annotations: annots)
            block_param_pairs = params.zip(method_type.block.params)

            unless block_param_pairs
              return Errors::IncompatibleBlockParameters.new(
                node: node,
                method_type: method_type
              )
            end

            var_types = self.var_types.dup

            block_param_pairs.each do |param, type|
              if param.type
                relation = Subtyping::Relation.new(
                  sub_type: type,
                  super_type: param.type
                )

                checker.check(relation, constraints: constraints).else do
                  return Errors::BlockParameterTypeMismatch.new(
                    node: param.node,
                    expected: type,
                    actual: param.type
                  )
                end

                var_types[param.var] = param.type
              else
                var_types[param.var] = type
              end
            end

            method_type.subst(constraints.subst(checker)).yield_self do |method_type|
              if block_body
                return_type = if annots.break_type
                                union_type(method_type.return_type, annots.break_type)
                              else
                                method_type.return_type
                              end
                Steep.logger.debug("return_type = #{return_type}")

                block_context = BlockContext.new(body_type: annots.block_type,
                                                 break_type: annots.break_type || method_type.return_type)
                Steep.logger.debug("block_context { body_type: #{block_context.body_type}, break_type=#{block_context.break_type} }")

                for_block = self.class.new(
                  checker: checker,
                  source: source,
                  annotations: annotations + annots,
                  var_types: var_types,
                  block_context: block_context,
                  typing: typing,
                  method_context: method_context,
                  module_context: self.module_context,
                  self_type: annots.self_type || self_type
                )

                each_child_node(block_params) do |p|
                  for_block.synthesize(p)
                end

                block_type = for_block.synthesize(block_body)

                result = checker.check(Subtyping::Relation.new(
                  sub_type: annots.block_type || block_type,
                  super_type: method_type.block.return_type
                ), constraints: constraints)

                if result.success?
                  return_type.subst(constraints.subst(checker))
                else
                  typing.add_error Errors::BlockTypeMismatch.new(node: node,
                                                                 expected: method_type.block.return_type,
                                                                 actual: annots.block_type || block_type,
                                                                 result: result)
                  return_type
                end
              end
            end

          when !method_type.block && !block_params && !block_body
            # OK, without block
            method_type.return_type

          when !method_type.block && block_params && block_body
            Errors::UnexpectedBlockGiven.new(
              node: node,
              method_type: method_type
            )

          when method_type.block && !block_params && !block_body
            Errors::RequiredBlockMissing.new(
              node: node,
              method_type: method_type
            )

          else
            raise "Unexpected case condition"

          end
        end
      end
    end

    def variable_type(var)
      var_types[var] || absolute_type(annotations.lookup_var_type(var.name))
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

    def test_args(params:, arguments:)
      params.each_missing_argument arguments do |_|
        return nil
      end

      params.each_extra_argument arguments do |_|
        return nil
      end

      params.each_missing_keyword arguments do |_|
        return nil
      end

      params.each_extra_keyword arguments do |_|
        return nil
      end

      self.class.argument_typing_pairs(params: params, arguments: arguments.dup)
    end

    def applicable_args?(params:, arguments:)
      params.each_missing_argument arguments do |_|
        return false
      end

      params.each_extra_argument arguments do |_|
        return false
      end

      params.each_missing_keyword arguments do |_|
        return false
      end

      params.each_extra_keyword arguments do |_|
        return false
      end

      all_args = arguments.dup

      self.class.argument_typing_pairs(params: params, arguments: arguments.dup).each do |(param_type, argument)|
        all_args.delete_if {|a| a.equal?(argument) }

        check(argument, param_type) do |_, _|
          return false
        end
      end

      all_args.each do |arg|
        synthesize(arg)
      end

      true
    end

    def self.block_param_typing_pairs(param_types: , param_nodes:)
      pairs = []

      param_types.required.each.with_index do |type, index|
        if (param = param_nodes[index])
          pairs << [param, type]
        end
      end

      pairs
    end

    def self.argument_typing_pairs(params:, arguments:)
      keywords = {}
      unless params.required_keywords.empty? && params.optional_keywords.empty? && !params.rest_keywords
        # has keyword args
        last_arg = arguments.last
        if last_arg&.type == :hash
          arguments.pop

          last_arg.children.each do |elem|
            case elem.type
            when :pair
              key, value = elem.children
              if key.type == :sym
                name = key.children[0]

                keywords[name] = value
              end
            end
          end
        end
      end

      pairs = []

      params.flat_unnamed_params.each do |param_type|
        arg = arguments.shift
        pairs << [param_type.last, arg] if arg
      end

      if params.rest
        arguments.each do |arg|
          pairs << [params.rest, arg]
        end
      end

      params.flat_keywords.each do |name, type|
        arg = keywords.delete(name)
        if arg
          pairs << [type, arg]
        end
      end

      if params.rest_keywords
        keywords.each_value do |arg|
          pairs << [params.rest_keywords, arg]
        end
      end

      pairs
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
          env[a.children.first] = Types.array_instance(type.params.rest)
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
            env[node.children[0]] = Types::Name.instance(
              name: "::Hash",
              params: [
                Types::Name.instance(name: :Symbol),
                ty
              ]
            )
          end
        end
      end

      env
    end

    def self.valid_parameter_env?(env, nodes, params)
      env.size == nodes.size && env.size == params.size
    end

    def absolute_type(type)
      checker.builder.absolute_type(type, current: nil)
    end

    def union_type(*types)
      types_ = checker.compact(types.compact)

      if types_.size == 1
        types_.first
      else
        AST::Types::Union.new(types: types_)
      end
    end

    def validate_method_definitions(node, module_name)
      signature = checker.builder.signatures.find_class_or_module(module_name.name)

      signature.members.each do |member|
        if member.is_a?(AST::Signature::Members::Method)
          case
          when member.instance_method?
            unless module_context.defined_instance_methods.include?(member.name) || annotations.dynamics.member?(member.name)
              typing.add_error Errors::MethodDefinitionMissing.new(node: node,
                                                                   module_name: module_name.name,
                                                                   kind: :instance,
                                                                   missing_method: member.name)
            end
          when member.module_method?
            unless module_context.defined_module_methods.include?(member.name)
              typing.add_error Errors::MethodDefinitionMissing.new(node: node,
                                                                   module_name: module_name.name,
                                                                   kind: :module,
                                                                   missing_method: member.name)
            end
          end
        end
      end

      annotations.dynamics.each do |method_name|
        unless signature.members.any? {|sig| sig.is_a?(AST::Signature::Members::Method) && sig.name == method_name }
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

      typing.add_typing node, Types.any
    end

    def self_class?(node)
      node.type == :send && node.children[0]&.type == :self && node.children[1] == :class
    end
  end
end
