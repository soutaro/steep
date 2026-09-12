module Steep
  module Server
    class GotoResolver
      attr_reader :database

      def initialize(database:)
        @database = database
      end

      def goto(kind:, from:, result:)
        locations = [] #: Array[location]

        case kind
        when :definition, :implementation
          # A constant and a method have a Ruby side and an RBS side, and the jump goes to the other side of where the cursor is
          source =
            if kind == :implementation || from == :rbs
              :ruby
            else
              :rbs
            end #: TypeCheckDatabase::Location::source

          if constant = result[:constant]
            locations.concat(definition_locations(constant, source: source))
          end

          result[:method_names]&.each do |method_name|
            locations.concat(method_definition_locations(method_name, source: source))
          end

          # A type name is a reference to an RBS declaration wherever it is written, and its implementation is in Ruby
          if type_name = result[:type_name]
            locations.concat(definition_locations(type_name, source: kind == :implementation ? :ruby : :rbs))
          end
        when :type_definition
          if type = result[:type]
            each_type_name(type) do |type_name|
              locations.concat(definition_locations(type_name, source: :rbs))
            end
          end
        end

        locations.uniq
      end

      def query_definition(name_string)
        name = GotoResolver.parse_name(name_string)

        kind =
          case name
          when RBS::TypeName
            "type_name"
          when InstanceMethodName
            "instance_method"
          when SingletonMethodName
            "singleton_method"
          else
            "unknown"
          end #: CustomMethods::Query__Definition::kind

        locations = [] #: Array[CustomMethods::Query__Definition::location]

        case name
        when RBS::TypeName
          database.definitions(name.to_s).each do |location|
            locations << query_location(location)
          end
        when InstanceMethodName, SingletonMethodName
          method_definitions(name.to_s).each do |location|
            locations << query_location(location)
          end
        end

        { name: name_string, kind: kind, locations: locations.uniq }
      end

      def self.parse_name(name_string)
        return nil if name_string.nil? || name_string.empty?

        if index = name_string.index("#")
          type_part = name_string[0...index] or return nil
          method_part = name_string[(index + 1)..] or return nil
          return nil if type_part.empty? || method_part.empty?

          type_name = parse_type_name(type_part) or return nil
          InstanceMethodName.new(type_name: type_name, method_name: method_part.to_sym)
        elsif (index = name_string.rindex(".")) && index > 0
          type_part = name_string[0...index] or return nil
          method_part = name_string[(index + 1)..] or return nil
          return nil if type_part.empty? || method_part.empty?

          type_name = parse_type_name(type_part) or return nil
          SingletonMethodName.new(type_name: type_name, method_name: method_part.to_sym)
        else
          parse_type_name(name_string)
        end
      rescue RBS::ParsingError, StandardError
        nil
      end

      def self.parse_type_name(string)
        string = "::#{string}" unless string.start_with?("::")
        RBS::TypeName.parse(string)
      rescue RBS::ParsingError, StandardError
        nil
      end

      def each_type_name(type_string, &block)
        type =
          begin
            RBS::Parser.parse_type(type_string, variables: [])
          rescue RBS::ParsingError
            return
          end
        type or return

        names = [] #: Array[RBS::TypeName]
        collect_type_names(type, names)
        names.uniq.each(&block)
      end

      private

      def collect_type_names(type, names)
        case type
        when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias
          names << type.name if type.name.absolute?
        when RBS::Types::Literal
          case type.literal
          when Integer
            names << builtin_name(:Integer)
          when String
            names << builtin_name(:String)
          when Symbol
            names << builtin_name(:Symbol)
          when true
            names << builtin_name(:TrueClass)
          when false
            names << builtin_name(:FalseClass)
          end
        when RBS::Types::Bases::Nil
          names << builtin_name(:NilClass)
        when RBS::Types::Bases::Bool
          names << builtin_name(:TrueClass)
          names << builtin_name(:FalseClass)
        end

        type.each_type do |child|
          collect_type_names(child, names)
        end
      end

      def builtin_name(name)
        RBS::TypeName.new(name: name, namespace: RBS::Namespace.root)
      end

      def definition_locations(name, source:)
        filter_source(database.definitions(name.to_s), source).map { lsp_location(_1) }
      end

      def method_definition_locations(name, source:)
        method_definitions(name, source: source).map { lsp_location(_1) }
      end

      def method_definitions(name, source: nil)
        definitions = filter_source(database.definitions(name), source)

        if definitions.empty? && name.end_with?(".new")
          definitions = filter_source(database.definitions("#{name.delete_suffix(".new")}#initialize"), source)
        end

        definitions
      end

      def filter_source(locations, source)
        if source
          locations.select { _1.source == source }
        else
          locations
        end
      end

      def lsp_location(location)
        { uri: PathHelper.to_uri(location.path).to_s, range: location.lsp_range }
      end

      def query_location(location)
        source =
          case location.source
          when :rbs
            "rbs"
          when :ruby
            "ruby"
          end #: CustomMethods::Query__Definition::source

        { uri: PathHelper.to_uri(location.path).to_s, range: location.lsp_range, source: source }
      end
    end
  end
end
