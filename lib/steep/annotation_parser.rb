module Steep
  class AnnotationParser
    VAR_NAME = /[a-z][A-Za-z0-9_]*/
    METHOD_NAME = Regexp.union(
      /[^.:\s]+/
    )
    CONST_NAME = Regexp.union(
      /(::)?([A-Z][A-Za-z0-9_]*::)*[A-Z][A-Za-z0-9_]*/
    )
    DYNAMIC_NAME = /(self\??\.)?#{METHOD_NAME}/
    IVAR_NAME = /@[^:\s]+/

    attr_reader :factory

    def initialize(factory:)
      @factory = factory
    end

    class SyntaxError < StandardError
      attr_reader :source
      attr_reader :location

      def initialize(source:, location:, exn: nil, message: nil)
        @source = source
        @location = location

        if exn
          message =
            case exn
            when RBS::ParsingError
              Diagnostic::Signature::SyntaxError.parser_syntax_error_message(exn)
            else
              exn.message
            end
        end

        super message
      end
    end

    TYPE = /(?<type>.*)/
    COLON = /\s*:\s*/

    PARAM = /[A-Z][A-Za-z0-9_]*/
    TYPE_PARAMS = /(\[(?<params>#{PARAM}(,\s*#{PARAM})*)\])?/

    def parse_type(match, name = :type, location:)
      string = match[name] or raise
      st, en = match.offset(name)
      st or raise
      en or raise
      loc = RBS::Location.new(location.buffer, location.start_pos + st, location.start_pos + en)

      type =
        begin
          RBS::Parser.parse_type(string)
        rescue RBS::ParsingError => exn
          raise SyntaxError.new(source: string, location: loc, exn: exn)
        end or raise

      unless (type.location || raise).source == string.strip
        raise SyntaxError.new(source: string, location: loc, message: "Failed to parse a type in annotation")
      end

      factory.type(type)
    end

    def keyword_subject_type(keyword, name)
      /@type\s+#{keyword}\s+(?<name>#{name})#{COLON}#{TYPE}/
    end

    def keyword_and_type(keyword)
      /@type\s+#{keyword}#{COLON}#{TYPE}/
    end

    def parse(src, location:)
      case src
      when keyword_subject_type("var", VAR_NAME)
        Regexp.last_match.yield_self do |match|
          match or raise
          name = match[:name] or raise

          AST::Annotation::VarType.new(name: name.to_sym,
                                       type: parse_type(match, location: location),
                                       location: location)
        end

      when keyword_subject_type("method", METHOD_NAME)
        Regexp.last_match.yield_self do |match|
          match or raise
          name = match[:name] or raise
          type = match[:type] or raise

          method_type = factory.method_type(RBS::Parser.parse_method_type(type) || raise, method_decls: Set[])

          AST::Annotation::MethodType.new(name: name.to_sym,
                                          type: method_type,
                                          location: location)
        end

      when keyword_subject_type("const", CONST_NAME)
        Regexp.last_match.yield_self do |match|
          match or raise
          name = match[:name] or raise
          type = parse_type(match, location: location)

          AST::Annotation::ConstType.new(name: TypeName(name), type: type, location: location)
        end

      when keyword_subject_type("ivar", IVAR_NAME)
        Regexp.last_match.yield_self do |match|
          match or raise
          name = match[:name] or raise
          type = parse_type(match, location: location)

          AST::Annotation::IvarType.new(name: name.to_sym,
                                         type: type,
                                         location: location)
        end

      when keyword_and_type("return")
        Regexp.last_match.yield_self do |match|
          match or raise
          type = parse_type(match, location: location)
          AST::Annotation::ReturnType.new(type: type, location: location)
        end

      when keyword_and_type("block")
        Regexp.last_match.yield_self do |match|
          match or raise
          type = parse_type(match, location: location)
          AST::Annotation::BlockType.new(type: type, location: location)
        end

      when keyword_and_type("self")
        Regexp.last_match.yield_self do |match|
          match or raise
          type = parse_type(match, location: location)
          AST::Annotation::SelfType.new(type: type, location: location)
        end

      when keyword_and_type("instance")
        Regexp.last_match.yield_self do |match|
          match or raise
          type = parse_type(match, location: location)
          AST::Annotation::InstanceType.new(type: type, location: location)
        end

      when keyword_and_type("module")
        Regexp.last_match.yield_self do |match|
          match or raise
          type = parse_type(match, location: location)
          AST::Annotation::ModuleType.new(type: type, location: location)
        end

      when keyword_and_type("break")
        Regexp.last_match.yield_self do |match|
          match or raise
          type = parse_type(match, location: location)

          AST::Annotation::BreakType.new(type: type, location: location)
        end

      when /@dynamic\s+(?<names>(#{DYNAMIC_NAME}\s*,\s*)*#{DYNAMIC_NAME})/
        Regexp.last_match.yield_self do |match|
          match or raise
          names = (match[:names] || raise).split(/\s*,\s*/)

          AST::Annotation::Dynamic.new(
            names: names.map {|name|
              case
              when name.delete_prefix!("self.")
                AST::Annotation::Dynamic::Name.new(name: name.to_sym, kind: :module)
              when name.delete_prefix!("self?.")
                AST::Annotation::Dynamic::Name.new(name: name.to_sym, kind: :module_instance)
              else
                AST::Annotation::Dynamic::Name.new(name: name.to_sym, kind: :instance)
              end
            },
            location: location
          )
        end

      when /@implements\s+(?<name>#{CONST_NAME})#{TYPE_PARAMS}$/
        Regexp.last_match.yield_self do |match|
          match or raise
          type_name = TypeName(match[:name] || raise)
          params = match[:params]&.yield_self {|params| params.split(/,/).map {|param| param.strip.to_sym } } || []

          name = AST::Annotation::Implements::Module.new(name: type_name, args: params)
          AST::Annotation::Implements.new(name: name, location: location)
        end
      end

    rescue RBS::ParsingError => exn
      raise SyntaxError.new(source: src, location: location, exn: exn)
    end
  end
end
