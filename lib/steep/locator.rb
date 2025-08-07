module Steep
  class Locator
    extend NodeHelper

    module TypeNameLocator
      def type_name_at(position, type)
        buffer = type.location&.buffer or raise

        locator = RBS::Locator.new(buffer: buffer, decls: [], dirs: [])
        components = [] #: Array[RBS::Locator::component]

        if locator.find_in_type(position, type: type, array: components)
          symbol, type, * = components
          if symbol.is_a?(Symbol)
            case type
            when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Alias, RBS::Types::Interface
              if symbol == :name
                type_loc = type.location or raise
                name_loc = type.location[:name]
                return [type.name, name_loc]
              end
            end
          end
        end
      end
    end

    NodeResult = Data.define(:node, :parents)

    TypeAssertionResult = Data.define(:assertion, :node)

    TypeApplicationResult = Data.define(:application, :node)

    AnnotationResult = Data.define(:annotation, :node, :block)

    CommentResult = Data.define(:comment, :node)

    InlineAnnotationResult = Data.define(:annotation, :attached_ast)

    InlineTypeResult = Data.define(:type, :annotation_result)

    InlineTypeNameResult = Data.define(:type_name, :location, :enclosing_result)

    class TypeAssertionResult
      include TypeNameLocator

      def locate_type_name(position, nesting, subtyping, type_vars)
        if type = assertion.rbs_type(nesting, subtyping, type_vars)
          location = type.location or raise
          if location.start_pos <= position && position <= location.end_pos
            if loc = type_name_at(position, type)
              return loc
            end
          end
        end
      end
    end

    class TypeApplicationResult
      include TypeNameLocator

      def locate_type_name(position, nesting, subtyping, type_vars)
        application.each_rbs_type(nesting, subtyping, type_vars) do |type|
          location = type.location or raise
          if location.start_pos <= position && position <= location.end_pos
            if loc = type_name_at(position, type)
              return loc
            end
          end
        end

        nil
      end
    end

    class Ruby
      include NodeHelper

      attr_reader :source

      def initialize(source)
        @source = source
      end

      def find(line, column)
        position = source.buffer.loc_to_pos([line, column])

        if nodes = source.find_heredoc_nodes(line, column, position)
          heredoc_node, *parent_nodes = nodes
          heredoc_node or raise
          each_child_node(heredoc_node) do |child_node|
            if result = find_ruby_node_in(position, child_node, nodes)
              return ruby_result_from_node(result, position)
            end
          end
          return NodeResult.new(heredoc_node, parent_nodes)
        end

        if source.node && node = find_ruby_node_in(position, source.node, [])
          ruby_result_from_node(node, position)
        else
          comment = source.comments.find { _1.location.expression.begin_pos <= position && position <= _1.location.expression.end_pos }
          if comment
            CommentResult.new(comment, nil)
          end
        end
      end

      def ruby_result_from_node(node, position)
        case node.node.type
        when :assertion
          TypeAssertionResult.new(node.node.children[1], node)
        when :tapp
          application = node.node.children[1] #: AST::Node::TypeApplication
          TypeApplicationResult.new(application, node)
        else
          comment = source.comments.find do
            _1.location.expression.begin_pos <= position && position <= _1.location.expression.end_pos
          end

          if block_node = source.find_block_node([node.node, *node.parents])
            source.each_block_annotation(block_node) do |annotation|
              if location = annotation.location
                if location.start_pos <= position && position <= location.end_pos
                  return AnnotationResult.new(annotation, node, block_node)
                end
              end
            end
          end

          if comment
            return CommentResult.new(comment, NodeResult.new(node.node, node.parents))
          end

          node
        end
      end

      def find_ruby_node_in(position, node, parents)
        return unless node

        range = node.location.expression&.to_range

        return unless range

        if range.begin <= position && position <= range.end
          parents.unshift(node)
          each_child_node(node) do |child|
            if result = find_ruby_node_in(position, child, parents)
              return result
            end
          end

          parents.shift
          return NodeResult.new(node, parents)
        end
      end
    end

    class Inline
      attr_reader :source

      def initialize(source)
        @source = source
      end

      def find(line, column)
        position = source.buffer.loc_to_pos([line, column])

        source.declarations.each do |decl|
          if ast = find0(position, decl)
            return inline_result(position, ast)
          end
        end

        nil
      end

      def find0(position, ast)
        case ast
        when RBS::AST::Ruby::Declarations::ClassDecl
          if ast.location.start_pos <= position && position <= ast.location.end_pos
            # Check if position is within super class
            if ast.super_class
              if ast.super_class.location.start_pos <= position && position <= ast.super_class.location.end_pos
                # Check if position is on the super class type name
                if ast.super_class.type_name_location.start_pos <= position && position <= ast.super_class.type_name_location.end_pos
                  return InlineAnnotationResult.new(ast.super_class, ast)
                end
                # Check if position is on type arguments
                if ast.super_class.type_annotation
                  if ast.super_class.type_annotation.location.start_pos <= position && position <= ast.super_class.type_annotation.location.end_pos
                    return InlineAnnotationResult.new(ast.super_class.type_annotation, ast)
                  end
                end
              end
            end

            ast.members.each do |member|
              if sub = find0(position, member)
                return sub
              end
            end
          end
        when RBS::AST::Ruby::Declarations::ModuleDecl
          if ast.location.start_pos <= position && position <= ast.location.end_pos
            ast.members.each do |member|
              if sub = find0(position, member)
                return sub
              end
            end
          end
        when RBS::AST::Ruby::Members::DefMember
          case annotations = ast.method_type.type_annotations
          when RBS::AST::Ruby::Members::MethodTypeAnnotation::DocStyle
            if annotation = annotations.return_type_annotation
              if annotation.location.start_pos <= position && position <= annotation.location.end_pos
                return InlineAnnotationResult.new(annotations.return_type_annotation, ast)
              end
            end
          when Array
            annotations.each do |annotation|
              case annotation
              when RBS::AST::Ruby::Annotations::ColonMethodTypeAnnotation
                if annotation.location.start_pos <= position && position <= annotation.location.end_pos
                  return InlineAnnotationResult.new(annotation, ast)
                end
              when RBS::AST::Ruby::Annotations::MethodTypesAnnotation
                if annotation.location.start_pos <= position && position <= annotation.location.end_pos
                  return InlineAnnotationResult.new(annotation, ast)
                end
              end
            end
          end
        when RBS::AST::Ruby::Members::IncludeMember, RBS::AST::Ruby::Members::ExtendMember, RBS::AST::Ruby::Members::PrependMember
          if ast.annotation.is_a?(RBS::AST::Ruby::Annotations::TypeApplicationAnnotation)
            if ast.annotation.location.start_pos <= position && position <= ast.annotation.location.end_pos
              return InlineAnnotationResult.new(ast.annotation, ast)
            end
          end
        when RBS::AST::Ruby::Members::AttrReaderMember, RBS::AST::Ruby::Members::AttrWriterMember, RBS::AST::Ruby::Members::AttrAccessorMember
          if annotation = ast.type_annotation
            if annotation.location.start_pos <= position && position <= annotation.location.end_pos
              return InlineAnnotationResult.new(annotation, ast)
            end
          end
        when RBS::AST::Ruby::Members::InstanceVariableMember
          annotation = ast.annotation
          if annotation.location.start_pos <= position && position <= annotation.location.end_pos
            return InlineAnnotationResult.new(annotation, ast)
          end
        when RBS::AST::Ruby::Declarations::ConstantDecl
          if annotation = ast.type_annotation
            if annotation.location.start_pos <= position && position <= annotation.location.end_pos
              return InlineAnnotationResult.new(annotation, ast)
            end
          end
        end

        nil
      end

      def inline_result(position, result)
        type_result = nil #: InlineTypeResult?

        case result.annotation
        when RBS::AST::Ruby::Annotations::ReturnTypeAnnotation
          if type_location = result.annotation.return_type.location
            if type_location.start_pos <= position && position <= type_location.end_pos
              type_result = InlineTypeResult.new(result.annotation.return_type, result)
            end
          end
        when RBS::AST::Ruby::Annotations::ColonMethodTypeAnnotation
          type = result.annotation.method_type.each_type.find do |type|
            if type_location = type.location
              type_location.start_pos <= position && position <= type_location.end_pos
            end
          end

          if type
            type_result = InlineTypeResult.new(type, result)
          end
        when RBS::AST::Ruby::Annotations::MethodTypesAnnotation
          overload = result.annotation.overloads.find do
            if location = _1.method_type.location
              location.start_pos <= position && position <= location.end_pos
            end
          end

          if overload
            type = overload.method_type.each_type.find do |type|
              if type_location = type.location
                type_location.start_pos <= position && position <= type_location.end_pos
              end
            end

            if type
              type_result = InlineTypeResult.new(type, result)
            end
          end
        when RBS::AST::Ruby::Annotations::TypeApplicationAnnotation
          # Find type argument that contains the position
          type = result.annotation.type_args.find do |type_arg|
            if type_location = type_arg.location
              type_location.start_pos <= position && position <= type_location.end_pos
            end
          end

          if type
            type_result = InlineTypeResult.new(type, result)
          end
        when RBS::AST::Ruby::Annotations::NodeTypeAssertion
          # Handle type annotations for attr_reader/writer/accessor
          if type_location = result.annotation.type.location
            if type_location.start_pos <= position && position <= type_location.end_pos
              type_result = InlineTypeResult.new(result.annotation.type, result)
            end
          end
        when RBS::AST::Ruby::Annotations::InstanceVariableAnnotation
          # Handle type annotations for instance variables
          if type_location = result.annotation.type.location
            if type_location.start_pos <= position && position <= type_location.end_pos
              type_result = InlineTypeResult.new(result.annotation.type, result)
            end
          end
        when RBS::AST::Ruby::Declarations::ClassDecl::SuperClass
          # Handle super class type name navigation
          if result.annotation.type_name_location.start_pos <= position && position <= result.annotation.type_name_location.end_pos
            # For super class type name, we can directly create the type name result
            return InlineTypeNameResult.new(
              result.annotation.type_name,
              result.annotation.type_name_location,
              result
            )
          elsif result.annotation.type_annotation
            # Handle type arguments
            type = result.annotation.type_annotation.type_args.find do |type_arg|
              if type_location = type_arg.location
                type_location.start_pos <= position && position <= type_location.end_pos
              end
            end
            if type
              type_result = InlineTypeResult.new(type, result)
            end
          end
        end

        if type_result
          type_name_result(position, type_result)
        else
          result
        end
      end

      def type_name_result(position, result)
        locator = RBS::Locator.new(buffer: source.buffer, decls: [], dirs: [])
        components = [] #: Array[RBS::Locator::component]

        if locator.find_in_type(position, type: result.type, array: components)
          symbol, type, * = components
          if symbol.is_a?(Symbol)
            type_name = nil #: RBS::TypeName?
            location = nil #: RBS::Location?

            case type
            when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Alias, RBS::Types::Interface
              if symbol == :name
                type_loc = type.location or raise
                type_name = type.name
                location = type_loc[:name] or raise
              end
            end

            if type_name && location
              return InlineTypeNameResult.new(type_name, location, result)
            end
          end
        end

        result
      end
    end
  end
end
