module Steep
  module Index
    class SourceIndex
      class ConstantEntry
        attr_reader :name

        attr_reader :definitions
        attr_reader :references

        def initialize(name:)
          @name = name

          @definitions = Set[].compare_by_identity
          @references = Set[].compare_by_identity
        end

        def add_definition(node)
          case node.type
          when :casgn, :class, :module
            @definitions << node
          else
            raise "Unexpected constant definition: #{node.type}"
          end

          self
        end

        def add_reference(node)
          case node.type
          when :const
            @references << node
          else
            raise "Unexpected constant reference: #{node.type}"
          end

          self
        end

        def merge!(other)
          definitions.merge(other.definitions)
          references.merge(other.references)
          self
        end
      end

      attr_reader :source
      attr_reader :constant_index

      attr_reader :parent
      attr_reader :count
      attr_reader :parent_count

      def initialize(source:, parent: nil)
        @source = source
        @parent = parent
        @parent_count = parent&.count

        @count = @parent_count || 0

        @constant_index = {}
      end

      def new_child
        SourceIndex.new(source: source, parent: self)
      end

      def merge!(child)
        raise unless child.parent == self
        raise unless child.parent_count == count

        constant_index.merge!(child.constant_index) do |_, entry, child_entry|
          entry.merge!(child_entry)
        end

        @count = child.count + 1
      end

      def add_definition(constant:, definition:)
        @count += 1
        entry(constant: constant).add_definition(definition)
        self
      end

      def add_reference(constant:, ref:)
        @count += 1
        entry(constant: constant).add_reference(ref)
        self
      end

      def entry(constant:)
        case
        when constant
          constant_index[constant] ||= ConstantEntry.new(name: constant)
        else
          raise
        end
      end
    end
  end
end
