module Steep
  module TypeInference
    class MethodCall
      class MethodDecl
        attr_reader :method_name
        attr_reader :method_def

        def initialize(method_name:, method_def:)
          @method_name = method_name
          @method_def = method_def
        end

        def hash
          method_name.hash
          # RBS::MethodType doesn't have #hash
        end

        def ==(other)
          other.is_a?(MethodDecl) && other.method_name == method_name && other.method_def == method_def
        end

        alias eql? ==

        def method_type
          method_def.type
        end
      end

      MethodContext = _ = Struct.new(:method_name, keyword_init: true) do
        # @implements MethodContext

        def to_s
          "@#{method_name}"
        end
      end

      ModuleContext = _ = Struct.new(:type_name, keyword_init: true) do
        # @implements ModuleContext

        def to_s
          "@#{type_name}@"
        end
      end

      TopLevelContext = _ = Class.new() do
        def to_s
          "@<main>"
        end
      end

      UnknownContext = _ = Class.new() do
        def to_s
          "@<unknown>"
        end
      end


      class Base
        attr_reader :node
        attr_reader :context
        attr_reader :method_name
        attr_reader :return_type
        attr_reader :receiver_type

        def initialize(node:, context:, method_name:, receiver_type:, return_type:)
          @node = node
          @context = context
          @method_name = method_name
          @receiver_type = receiver_type
          @return_type = return_type
        end

        def with_return_type(new_type)
          dup.tap do |copy|
            copy.instance_eval do
              @return_type = new_type
            end
          end
        end
      end

      class Typed < Base
        attr_reader :actual_method_type
        attr_reader :method_decls

        def initialize(node:, context:, method_name:, receiver_type:, actual_method_type:, method_decls:, return_type:)
          super(node: node, context: context, method_name: method_name, receiver_type: receiver_type, return_type: return_type)
          @actual_method_type = actual_method_type
          @method_decls = method_decls
        end

        def pure?
          method_decls.all? do |method_decl|
            case member = method_decl.method_def.member
            when RBS::AST::Members::MethodDefinition
              member.annotations.any? {|annotation| annotation.string == "pure" }
            when RBS::AST::Members::Attribute
              true
            end
          end
        end
      end

      class Special < Typed
      end

      class Untyped < Base
        def initialize(node:, context:, method_name:)
          super(node: node, context: context, method_name: method_name, receiver_type: AST::Types::Any.new, return_type: AST::Types::Any.new)
        end
      end

      class NoMethodError < Base
        attr_reader :error

        def initialize(node:, context:, method_name:, receiver_type:, error:)
          super(node: node, context: context, method_name: method_name, receiver_type: receiver_type, return_type: AST::Types::Any.new)
          @error = error
        end
      end

      class Error < Base
        attr_reader :errors
        attr_reader :method_decls

        def initialize(node:, context:, method_name:, receiver_type:, errors:, method_decls: Set[], return_type: AST::Types::Any.new)
          super(node: node, context: context, method_name: method_name, receiver_type: receiver_type, return_type: return_type)
          @method_decls = method_decls
          @errors = errors
        end
      end
    end
  end
end
