module Steep
  module ParserCompatibility
    # Configuration for parser backend selection
    @parser_engine = case ENV['STEEP_PARSER_ENGINE']&.to_sym
                     when :prism
                       :prism
                     when :parser
                       :parser
                     else
                       :parser
                     end

    class << self
      attr_accessor :parser_engine

      def use_prism!
        @parser_engine = :prism
        nil
      end

      def use_parser!
        @parser_engine = :parser
        nil
      end

      def prism?
        @parser_engine == :prism
      end

      def parser?
        @parser_engine == :parser
      end

      # Factory method to create the appropriate parser class
      def parser_class
        case @parser_engine
        when :prism
          require 'prism'
          Prism::Translation::Parser33
        when :parser
          require 'parser/ruby33'
          Parser::Ruby33
        else
          raise ArgumentError, "Unknown parser engine: #{@parser_engine}"
        end
      end

      # Factory method for AST node creation
      def create_node(type, children, properties = {})
        case @parser_engine
        when :prism, :parser
          Parser::AST::Node.new(type, children, properties)
        else
          raise ArgumentError, "Unknown parser engine: #{@parser_engine}"
        end
      end

      # Factory method for source buffer creation
      def create_buffer(name, source)
        Parser::Source::Buffer.new(name, 1, source: source)
      end

      # Factory method for source map creation
      def create_source_map(range)
        Parser::Source::Map.new(range)
      end
    end
  end
end
