module Steep
  module Server
    class GotoResolver
      attr_reader :database

      def initialize(database:)
        @database = database
      end

      def goto(kind:, symbols:)
        locations = [] #: Array[location]

        symbols.each do |symbol|
          name = symbol[:name]

          case symbol[:kind]
          when "constant"
            source =
              if kind == :implementation || symbol[:from] == "rbs"
                :ruby
              else
                :rbs
              end #: TypeCheckDatabase::Entry::source
            locations.concat(definition_locations(name, kind: :constant, source: source))
          when "method"
            source =
              if kind == :implementation || symbol[:from] == "rbs"
                :ruby
              else
                :rbs
              end #: TypeCheckDatabase::Entry::source
            locations.concat(method_definition_locations(name, source: source))
          when "type_name"
            if kind == :implementation
              locations.concat(definition_locations(name, kind: :constant, source: :ruby))
            else
              TYPE_NAME_KINDS.each do |type_kind|
                locations.concat(definition_locations(name, kind: type_kind, source: :rbs))
              end
            end
          end
        end

        locations.uniq
      end

      def query_definition(name_string)
        name = Services::GotoService.parse_name(name_string)

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
          TYPE_NAME_KINDS.each do |type_kind|
            database.definitions(name: name.to_s, kind: type_kind).each do |path, entry|
              locations << query_location(path, entry)
            end
          end
        when InstanceMethodName, SingletonMethodName
          method_definitions(name.to_s).each do |path, entry|
            locations << query_location(path, entry)
          end
        end

        { name: name_string, kind: kind, locations: locations.uniq }
      end

      TYPE_NAME_KINDS = [:constant, :interface, :type_alias] #: Array[TypeCheckDatabase::Entry::kind]

      private

      def definition_locations(name, kind:, source:)
        database.definitions(name: name, kind: kind).filter_map do |path, entry|
          if entry.source == source
            lsp_location(path, entry)
          end
        end
      end

      def method_definition_locations(name, source:)
        method_definitions(name).filter_map do |path, entry|
          if entry.source == source
            lsp_location(path, entry)
          end
        end
      end

      def method_definitions(name)
        definitions = database.definitions(name: name, kind: :method)

        if definitions.empty? && name.end_with?(".new")
          definitions = database.definitions(name: "#{name.delete_suffix(".new")}#initialize", kind: :method)
        end

        definitions
      end

      def lsp_location(path, entry)
        { uri: PathHelper.to_uri(path).to_s, range: entry.lsp_range }
      end

      def query_location(path, entry)
        source =
          case entry.source
          when :rbs
            "rbs"
          when :ruby
            "ruby"
          end #: CustomMethods::Query__Definition::source

        { uri: PathHelper.to_uri(path).to_s, range: entry.lsp_range, source: source }
      end
    end
  end
end
