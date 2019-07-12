module Steep
  class AnnotationParser
    VAR_NAME = /[a-z][A-Za-z0-9_]*/
    METHOD_NAME = Regexp.union(
      /[A-Za-z][A-Za-z0-9_]*[?!]?/
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

    TYPE = /(?<type>.*)/
    COLON = /\s*:\s*/

    PARAM = /[A-Z][A-Za-z0-9_]*/
    TYPE_PARAMS = /(\[(?<params>#{PARAM}(,\s*#{PARAM})*)\])?/

    def parse_type(string)
      factory.type(Ruby::Signature::Parser.parse_type(string))
    end

    # @type ${keyword} ${name}: ${type}
    # Example: @type const Foo::Bar: String
    #          @type var xyzzy: Array[String]
    def keyword_subject_type(keyword, name)
      /@type\s+#{keyword}\s+(?<name>#{name})#{COLON}#{TYPE}/
    end

    # @type ${keyword}: ${type}
    # Example: @type break: String
    #          @type self: Foo
    def keyword_and_type(keyword)
      /@type\s+#{keyword}#{COLON}#{TYPE}/
    end

    def parse(src, location:)
      case src
      when keyword_subject_type("var", VAR_NAME)
        Regexp.last_match.yield_self do |match|
          name = match[:name]
          type = match[:type]

          AST::Annotation::VarType.new(name: name.to_sym,
                                       type: parse_type(type),
                                       location: location)
        end

      when keyword_subject_type("method", METHOD_NAME)
        Regexp.last_match.yield_self do |match|
          name = match[:name]
          type = match[:type]

          method_type = factory.method_type(Ruby::Signature::Parser.parse_method_type(type))

          AST::Annotation::MethodType.new(name: name.to_sym,
                                          type: method_type,
                                          location: location)
        end

      when keyword_subject_type("const", CONST_NAME)
        Regexp.last_match.yield_self do |match|
          name = match[:name]
          type = parse_type(match[:type])

          AST::Annotation::ConstType.new(name: Names::Module.parse(name),
                                         type: type,
                                         location: location)
        end

      when keyword_subject_type("ivar", IVAR_NAME)
        Regexp.last_match.yield_self do |match|
          name = match[:name]
          type = parse_type(match[:type])

          AST::Annotation::IvarType.new(name: name.to_sym,
                                         type: type,
                                         location: location)
        end

      when keyword_and_type("return")
        Regexp.last_match.yield_self do |match|
          type = parse_type(match[:type])
          AST::Annotation::ReturnType.new(type: type, location: location)
        end

      when keyword_and_type("block")
        Regexp.last_match.yield_self do |match|
          type = parse_type(match[:type])
          AST::Annotation::BlockType.new(type: type, location: location)
        end

      when keyword_and_type("self")
        Regexp.last_match.yield_self do |match|
          type = parse_type(match[:type])
          AST::Annotation::SelfType.new(type: type, location: location)
        end

      when keyword_and_type("instance")
        Regexp.last_match.yield_self do |match|
          type = parse_type(match[:type])
          AST::Annotation::InstanceType.new(type: type, location: location)
        end

      when keyword_and_type("module")
        Regexp.last_match.yield_self do |match|
          type = parse_type(match[:type])
          AST::Annotation::ModuleType.new(type: type, location: location)
        end

      when keyword_and_type("break")
        Regexp.last_match.yield_self do |match|
          type = parse_type(match[:type])
          AST::Annotation::BreakType.new(type: type, location: location)
        end

      when /@dynamic\s+(?<names>(#{DYNAMIC_NAME}\s*,\s*)*#{DYNAMIC_NAME})/
        Regexp.last_match.yield_self do |match|
          names = match[:names].split(/\s*,\s*/)

          AST::Annotation::Dynamic.new(
            names: names.map {|name|
              case name
              when /^self\./
                AST::Annotation::Dynamic::Name.new(name: name[5..].to_sym, kind: :module)
              when /^self\?\./
                AST::Annotation::Dynamic::Name.new(name: name[6..].to_sym, kind: :module_instance)
              else
                AST::Annotation::Dynamic::Name.new(name: name.to_sym, kind: :instance)
              end
            },
            location: location
          )
        end

      when /@implements\s+(?<name>#{CONST_NAME})#{TYPE_PARAMS}$/
        Regexp.last_match.yield_self do |match|
          type_name = Names::Module.parse(match[:name])
          params = match[:params]&.yield_self {|params| params.split(/,/).map {|param| param.strip.to_sym } } || []

          name = AST::Annotation::Implements::Module.new(name: type_name, args: params)
          AST::Annotation::Implements.new(name: name, location: location)
        end
      end
    end
  end
end
