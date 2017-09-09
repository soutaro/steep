module Steep
  class TypeConstruction
    class MethodContext
      attr_reader :name
      attr_reader :method

      def initialize(name:, method:, method_type:, return_type:)
        @name = name
        @method = method
        @return_type = return_type
        @method_type = method_type
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

      def super_type
        method&.super_method&.types&.first
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

      def initialize(instance_type:, module_type:)
        @instance_type = instance_type
        @module_type = module_type
        @defined_instance_methods = Set.new
        @defined_module_methods = Set.new
      end
    end

    attr_reader :assignability
    attr_reader :source
    attr_reader :annotations
    attr_reader :var_types
    attr_reader :ivar_types
    attr_reader :typing
    attr_reader :method_context
    attr_reader :block_context
    attr_reader :module_context
    attr_reader :self_type

    def initialize(assignability:, source:, annotations:, var_types:, ivar_types: {}, typing:, self_type:, method_context:, block_context:, module_context:)
      @assignability = assignability
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
      if receiver_type
        entry = nil
        assignability.method_type receiver_type, method_name do |method|
          entry = method
        end
      end

      if (type = annotations.lookup_method_type(method_name))
        Interface::Method.new(types: [type], super_method: entry&.super_method)
      else
        entry
      end
    end

    def for_new_method(method_name, node, args:, self_type:)
      annots = source.annotations(block: node)

      self_type = annots.self_type || self_type

      entry = method_entry(method_name, receiver_type: self_type)
      method_type = entry&.types&.first
      if method_type
        var_types = TypeConstruction.parameter_types(args,
                                                     method_type)
        unless TypeConstruction.valid_parameter_env?(var_types, args, method_type.params)
          typing.add_error Errors::MethodParameterTypeMismatch.new(node: node)
        end
      else
        var_types = {}
      end

      method_context = MethodContext.new(
        name: method_name,
        method: entry,
        method_type: annotations.lookup_method_type(method_name),
        return_type: annots.return_type,
      )

      ivar_types = annots.ivar_types.keys.each.with_object({}) do |var, env|
        env[var] = annots.ivar_types[var]
      end

      self.class.new(
        assignability: assignability,
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

    def for_class(node)
      annots = source.annotations(block: node)

      if annots.implement_module
        signature = assignability.signatures[annots.implement_module]
        raise "Class implements should be an class: #{annots.instance_type}" unless signature.is_a?(Signature::Class)

        instance_type = Types::Name.instance(name: annots.implement_module)
        module_type = Types::Name.module(name: annots.implement_module)
      end

      module_context = ModuleContext.new(
        instance_type: annots.instance_type || instance_type,
        module_type: annots.module_type || module_type
      )

      self.class.new(
        assignability: assignability,
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
      case node.type
      when :begin
        type = each_child_node(node).map do |child|
          synthesize(child)
        end.last

        typing.add_typing(node, type)

      when :lvasgn
        var = node.children[0]
        rhs = node.children[1]

        type_assignment(var, rhs, node)

      when :lvar
        var = node.children[0]

        (variable_type(var) || Types::Any.new).tap do |type|
          typing.add_typing(node, type)
          typing.add_var_type(var, type)
        end

      when :ivasgn
        name = node.children[0]
        value = node.children[1]

        if (type = ivar_types[name])
          check(value, type) do |_, value_type|
            typing.add_error(Errors::IncompatibleAssignment.new(node: node, lhs_type: type, rhs_type: value_type))
          end
          typing.add_typing(node, type)
        else
          value_type = synthesize(value)
          typing.add_typing(node, value_type)
        end

      when :ivar
        type = ivar_types[node.children[0]] || Types::Any.new
        typing.add_typing(node, type)

      when :send
        type_send(node, with_block: false)

      when :super
        if self_type && method_context&.method
          if method_context.super_type
            ret_type = type_method_call(node: node,
                                        receiver_type: self_type,
                                        method_name: method_context.name,
                                        arguments: node.children,
                                        method_types: [method_context.super_type],
                                        with_block: false)
          else
            typing.add_error(Errors::UnexpectedSuper.new(node: node, method: method_context.name))
          end
        end

        typing.add_typing node, ret_type || Types::Any.new

      when :block
        send_node, params, block = node.children

        ret_type = type_send(send_node, with_block: true) do |recv_type, method_name, method_type|
          if method_type.block
            var_types_ = var_types.dup
            self.class.block_param_typing_pairs(param_types: method_type.block.params, param_nodes: params.children).each do |param_node, type|
              var = param_node.children[0]
              var_types_[var] = type
              typing.add_var_type(var, type)
            end

            annots = source.annotations(block: node)

            block_context = BlockContext.new(body_type: annots.block_type,
                                             break_type: method_type.return_type)

            for_block = self.class.new(
              assignability: assignability,
              source: source,
              annotations: annotations + annots,
              var_types: var_types_,
              block_context: block_context,
              typing: typing,
              method_context: method_context,
              module_context: module_context,
              self_type: annots.self_type || self_type
            )

            each_child_node(params) do |param|
              for_block.synthesize(param)
            end

            case method_type.block.return_type
            when Types::Var
              block_type = for_block.synthesize(block)
              method_type_ = method_type.instantiate(subst: { method_type.block.return_type.name => block_type })
              method_type_.return_type
            else
              for_block.check(block, method_type.block.return_type) do |expected, actual|
                typing.add_error Errors::BlockTypeMismatch.new(node: node, expected: expected, actual: actual)
              end
              method_type.return_type
            end

          else
            typing.add_error Errors::UnexpectedBlockGiven.new(node: node, type: recv_type, method: method_name)
            nil
          end
        end

        typing.add_typing(node, ret_type)

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
            new.check(node.children[2], return_type) do |_, actual_type|
              typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                  expected: return_type,
                                                                  actual: actual_type))
            end
          else
            new.synthesize(node.children[2])
          end
        end

        if module_context
          module_context.defined_instance_methods << node.children[0]
        end

        typing.add_typing(node, Types::Any.new)

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
              new.check(node.children[3], new.method_context.method_type.return_type) do |return_type, actual_type|
                typing.add_error(Errors::MethodBodyTypeMismatch.new(node: node,
                                                                    expected: return_type,
                                                                    actual: actual_type))
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

        typing.add_typing(node, Types::Name.instance(name: :Symbol))

      when :return
        value = node.children[0]

        if value
          if method_context&.return_type
            check(value, method_context.return_type) do |_, actual_type|
              typing.add_error(Errors::ReturnTypeMismatch.new(node: node,
                                                              expected: method_context.return_type,
                                                              actual: actual_type))
            end
          else
            synthesize(value)
          end
        end

        typing.add_typing(node, Types::Any.new)

      when :break
        value = node.children[0]

        if value
          if block_context&.break_type
            check(value, block_context.break_type) do |break_type, actual_type|
              typing.add_error Errors::BreakTypeMismatch.new(node: node,
                                                             expected: break_type,
                                                             actual: actual_type)
            end
          else
            synthesize(value)
          end
        end

        typing.add_typing(node, Types::Any.new)

      when :arg, :kwarg, :procarg0
        var = node.children[0]
        type = variable_type(var) || Types::Any.new

        typing.add_var_type(var, type)

      when :optarg, :kwoptarg
        var = node.children[0]
        rhs = node.children[1]
        type_assignment(var, rhs, node)

      when :int
        typing.add_typing(node, Types::Name.instance(name: :Integer))

      when :nil
        typing.add_typing(node, Types::Any.new)

      when :sym
        typing.add_typing(node, Types::Name.instance(name: :Symbol))

      when :str
        typing.add_typing(node, Types::Name.instance(name: :String))

      when :true, :false
        typing.add_typing(node, Types::Name.interface(name: :_Boolean))

      when :hash
        each_child_node(node) do |pair|
          raise "Unexpected non pair: #{pair.inspect}" unless pair.type == :pair
          each_child_node(pair) do |e|
            synthesize(e)
          end
        end

        typing.add_typing(node, Types::Any.new)

      when :dstr
        each_child_node(node) do |child|
          synthesize(child)
        end

        typing.add_typing(node, Types::Name.instance(name: :String))

      when :class
        for_class(node).tap do |constructor|
          constructor.synthesize(node.children[2])
          constructor.validate_method_definitions(node)
        end

        typing.add_typing(node, Types::Name.instance(name: :NilClass))

      when :module
        annots = source.annotations(block: node)

        if annots.implement_module
          signature = assignability.signatures[annots.implement_module]
          raise "Module instance should be an module: #{annots.instance_type}" unless signature.is_a?(Signature::Module)

          ty = Types::Name.instance(name: annots.implement_module)
          if signature.self_type
            instance_type = Types::Merge.new(types: [signature.self_type, ty])
          else
            instance_type = ty
          end
        end

        if annots.instance_type
          instance_type = annots.instance_type
        end

        module_context = ModuleContext.new(
          instance_type: instance_type,
          module_type: annots.module_type
        )

        for_class = self.class.new(
          assignability: assignability,
          source: source,
          annotations: annots,
          var_types: {},
          typing: typing,
          method_context: nil,
          block_context: nil,
          module_context: module_context,
          self_type: module_context.module_type
        )

        for_class.synthesize(node.children[1]) if node.children[1]
        for_class.validate_method_definitions(node)

        typing.add_typing(node, Types::Name.instance(name: :NilClass))

      when :self
        typing.add_typing(node, self_type || Types::Any.new)

      when :const
        type = annotations.lookup_const_type(node.children[1]) || Types::Any.new

        typing.add_typing(node, type)

      when :yield
        if method_context&.method_type
          if method_context.block_type
            block_type = method_context.block_type
            block_type.params.flat_unnamed_params.map(&:last).zip(node.children).each do |(type, node)|
              if node && type
                check(node, type) do |_, rhs_type|
                  typing.add_error(Errors::IncompatibleAssignment.new(node: node, lhs_type: type, rhs_type: rhs_type))
                end
              end
            end

            typing.add_typing(node, block_type.return_type)
          else
            typing.add_error(Errors::UnexpectedYield.new(node: node))
            typing.add_typing(node, Types::Any.new)
          end
        else
          typing.add_typing(node, Types::Any.new)
        end

      when :zsuper
        if method_context&.method
          if method_context.super_type
            typing.add_typing(node, method_context.super_type.return_type)
          else
            typing.add_error(Errors::UnexpectedSuper.new(node: node, method: method_context.name))
          end
        else
          typing.add_typing(node, Types::Any.new)
        end

      when :array
        if node.children.empty?
          typing.add_typing(node, Types::Name.instance(name: :Array, params: [Types::Any.new]))
        else
          types = node.children.map {|e| synthesize(e) }

          if types.uniq.size == 1
            typing.add_typing(node, Types::Name.instance(name: :Array, params: [types.first]))
          else
            typing.add_typing(node, Types::Name.instance(name: :Array, params: [Types::Any.new]))
          end
        end

      when :and
        types = each_child_node(node).map {|child| synthesize(child) }
        typing.add_typing(node, types.last)

      when :if
        cond, true_clause, false_clause = node.children
        synthesize cond
        true_type = synthesize(true_clause) if true_clause
        false_type = synthesize(false_clause) if false_clause

        typing.add_typing(node, union_type(true_type, false_type))

      else
        raise "Unexpected node: #{node.inspect}, #{node.location.line}"
      end
    end

    def check(node, type)
      type_ = synthesize(node)

      unless assignability.test(src: type_, dest: type)
        yield(type, type_)
      end
    end

    def type_assignment(var, rhs, node)
      lhs_type = variable_type(var)

      if rhs
        if lhs_type
          check(rhs, lhs_type) do |_, rhs_type|
            typing.add_error(Errors::IncompatibleAssignment.new(node: node, lhs_type: lhs_type, rhs_type: rhs_type))
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
        type = lhs_type || Types::Any.new
        typing.add_var_type(var, type)
        typing.add_typing(node, type)
        var_types[var] = type
        type
      end
    end

    def type_method_call(node:, receiver_type:, method_name:, method_types:, arguments:, with_block: false)
      method_type = method_types.flat_map do |type|
        next unless with_block == !!type.block

        var_types_mapping = {}

        type.type_params.each do |param|
          var_types_mapping[param] = []
        end

        catch :abort do
          pairs = test_args(params: type.params, arguments: arguments)
          if pairs
            arg_types = pairs.map {|(_, arg_node)| synthesize(arg_node) }

            pairs.each.with_index do |(param_type, _), index|
              arg_type = arg_types[index]

              case param_type
              when Types::Var
                var_types_mapping[param_type.name] << arg_type
              else
                unless assignability.test(src: arg_type, dest: param_type)
                  throw :abort
                end
              end
            end

            subst = var_types_mapping.each.with_object({}) do |(name, types), subst|
              unless types.empty?
                compacted_types = assignability.compact(types)

                if compacted_types.size > 1
                  subst[name] = Types::Union.new(types: compacted_types)
                else
                  subst[name] = compacted_types.first
                end
              end
            end

            type.instantiate(subst: subst)
          end
        end
      end.compact.first

      if method_type
        if block_given?
          return_type = yield(receiver_type, method_name, method_type)
        end
        return_type || method_type.return_type
      else
        arguments.each do |arg|
          synthesize(arg)
        end

        typing.add_error Errors::ArgumentTypeMismatch.new(node: node, type: receiver_type, method: method_name)
        nil
      end
    end

    def type_send(node, with_block:, &block)
      receiver, method_name, *args = node.children
      receiver_type = receiver ? synthesize(receiver) : self_type

      if receiver_type
        ret_type = assignability.method_type receiver_type, method_name do |method|
          if method
            type_method_call(node: node,
                             receiver_type: receiver_type,
                             method_name: method_name,
                             arguments: args,
                             method_types: method.types,
                             with_block: with_block,
                             &block)
          else
            args.each {|arg| synthesize(arg) }
            typing.add_error Errors::NoMethod.new(node: node, method: method_name, type: receiver_type)
            nil
          end
        end

        typing.add_typing node, ret_type
      else
        typing.add_typing node, Types::Any.new
      end
    end

    def variable_type(var)
      var_types[var] || annotations.lookup_var_type(var.name)
    end

    def each_child_node(node)
      if block_given?
        node.children.each do |child|
          if child.is_a?(AST::Node)
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
          env[a.children.first] = Types::Name.instance(name: :Array, params: [type.params.rest])
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
            env[node.children[0]] = Types::Name.instance(name: :Hash,
                                                         params: [Types::Name.instance(name: :Symbol), ty])
          end
        end
      end

      env
    end

    def self.valid_parameter_env?(env, nodes, params)
      env.size == nodes.size && env.size == params.size
    end

    def union_type(*types)
      types = types.compact.uniq

      if types.size == 1
        types.first
      else
        Types::Union.new(types: types)
      end
    end

    def validate_method_definitions(node)
      implements = annotations.implement_module
      if implements
        signature = assignability.signatures[implements]
        signature.members.each do |member|
          if member.is_a?(Signature::Members::InstanceMethod) || member.is_a?(Signature::Members::ModuleInstanceMethod)
            unless module_context.defined_instance_methods.include?(member.name)
              typing.add_error Errors::MethodDefinitionMissing.new(node: node,
                                                                   module_name: implements,
                                                                   kind: :instance,
                                                                   missing_method: member.name)
            end

          end
          if member.is_a?(Signature::Members::ModuleMethod) || member.is_a?(Signature::Members::ModuleInstanceMethod)
            unless module_context.defined_module_methods.include?(member.name)
              typing.add_error Errors::MethodDefinitionMissing.new(node: node,
                                                                   module_name: implements,
                                                                   kind: :module,
                                                                   missing_method: member.name)
            end
          end
        end
      end
    end
  end
end
