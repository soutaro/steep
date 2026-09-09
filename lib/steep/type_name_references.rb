module Steep
  # Collects the RBS type names referenced while type-checking a source file: a
  # sound over-approximation of the file's type dependencies, used to decide
  # whether it needs re-checking when a type changes.
  #
  # Names come from the type-resolution result (node types and resolved method
  # calls) and from annotations (`@type`, `@implements`), which influence
  # inference without appearing as a node's inferred type.
  class TypeNameReferences
    attr_reader :type_names

    def initialize
      @type_names = Set[]
    end

    def self.from_source_file(typing:, source:)
      collector = new()
      collector.collect_from_typing(typing)
      collector.collect_from_annotations(source)
      collector.type_names
    end

    def collect_from_typing(typing)
      typing.each_typing do |_node, type|
        add_type(type)
      end

      typing.method_calls.each_value do |call|
        add_type(call.receiver_type)
        add_type(call.return_type)

        if call.is_a?(TypeInference::MethodCall::Typed)
          call.actual_method_type.each_type do |type|
            add_type(type)
          end

          call.method_decls.each do |decl|
            # The type defining the called method: a change to it may change the signature.
            add_type_name(decl.method_name.type_name)
          end
        end
      end
    end

    def collect_from_annotations(source)
      source.each_annotation do |_node, annotations|
        annotations.each do |annotation|
          case annotation
          when AST::Annotation::Implements
            add_type_name(annotation.name.name)
          when AST::Annotation::Named, AST::Annotation::Typed
            type = annotation.type
            case type
            when Interface::MethodType
              type.each_type do |t|
                add_type(t)
              end
            else
              add_type(type)
            end
          else
            # `@dynamic` and other annotations carry no type to collect.
          end
        end
      end
    end

    def add_type(type)
      case type
      when AST::Types::Name::Base
        add_type_name(type.name)
      end

      type.each_child do |child|
        add_type(child)
      end
    end

    def add_type_name(type_name)
      type_names << type_name.absolute!
    end
  end
end
