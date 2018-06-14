class Steep::Parser

expect 1

rule

target: type_METHOD method_type { result = val[1] }
      | type_SIGNATURE signatures { result = val[1] }
      | type_ANNOTATION annotation { result = val[1] }
      | type_TYPE type { result = val[1] }

method_type:
  type_params params block_opt ARROW return_type {
    result = AST::MethodType.new(location: AST::Location.concat(*val.compact.map(&:location)),
                                 type_params: val[0],
                                 params: val[1]&.value,
                                 block: val[2],
                                 return_type: val[4])
  }

return_type: paren_type

params: { result = nil }
      | LPAREN params0 RPAREN { result = LocatedValue.new(location: val[0].location + val[2].location,
                                                          value: val[1]) }
      | simple_type { result = LocatedValue.new(location: val[0].location,
                                                value: AST::MethodType::Params::Required.new(location: val[0].location, type: val[0])) }

params0: required_param { result = AST::MethodType::Params::Required.new(location: val[0].location, type: val[0]) }
       | required_param COMMA params0 {
           location = val[0].location
           result = AST::MethodType::Params::Required.new(location: location,
                                                          type: val[0],
                                                          next_params: val[2])
         }
       | params1 { result = val[0] }

params1: optional_param { result = AST::MethodType::Params::Optional.new(location: val[0].first, type: val[0].last) }
       | optional_param COMMA params1 {
           location = val[0].first
           result = AST::MethodType::Params::Optional.new(type: val[0].last, location: location, next_params: val[2])
         }
       | params2 { result = val[0] }

params2: rest_param { result = AST::MethodType::Params::Rest.new(location: val[0].first, type: val[0].last) }
       | rest_param COMMA params3 {
           loc = val[0].first
           result = AST::MethodType::Params::Rest.new(location: loc, type: val[0].last, next_params: val[2])
         }
       | params3 { result = val[0] }

params3: required_keyword {
           location, name, type = val[0]
           result = AST::MethodType::Params::RequiredKeyword.new(location: location, name: name, type: type)
         }
       | optional_keyword {
           location, name, type = val[0]
           result = AST::MethodType::Params::OptionalKeyword.new(location: location, name: name, type: type)
         }
       | required_keyword COMMA params3 {
           location, name, type = val[0]
           result = AST::MethodType::Params::RequiredKeyword.new(location: location,
                                                                 name: name,
                                                                 type: type,
                                                                 next_params: val[2])
         }
       | optional_keyword COMMA params3 {
           location, name, type = val[0]
           result = AST::MethodType::Params::OptionalKeyword.new(location: location,
                                                                 name: name,
                                                                 type: type,
                                                                 next_params: val[2])
         }
       | params4 { result = val[0] }

params4: { result = nil }
       | STAR2 type {
           result = AST::MethodType::Params::RestKeyword.new(location: val[0].location + val[1].location,
                                                             type: val[1])
         }

required_param: type { result = val[0] }
optional_param: QUESTION type { result = [val[0].location + val[1].location,
                                          val[1]] }
rest_param: STAR type { result = [val[0].location + val[1].location,
                                  val[1]] }
required_keyword: keyword COLON type { result = [val[0].location + val[2].location,
                                                 val[0].value,
                                                 val[2]] }
optional_keyword: QUESTION keyword COLON type { result = [val[0].location + val[3].location,
                                                          val[1].value,
                                                          val[3]] }

block_opt: { result = nil }
         | LBRACE RBRACE {
             result = AST::MethodType::Block.new(params: nil,
                                                 return_type: nil,
                                                 location: val[0].location + val[1].location)
           }
         | LBRACE block_params ARROW type RBRACE {
             result = AST::MethodType::Block.new(params: val[1],
                                                 return_type: val[3],
                                                 location: val[0].location + val[4].location)
           }

block_params: { result = nil }
            | LPAREN block_params0 RPAREN {
                result = val[1]
              }

block_params0: required_param {
                 result = AST::MethodType::Params::Required.new(location: val[0].location,
                                                                type: val[0])
               }
             | required_param COMMA block_params0 {
                 result = AST::MethodType::Params::Required.new(location: val[0].location,
                                                                type: val[0],
                                                                next_params: val[2])
               }
             | block_params1 { result = val[0] }

block_params1: optional_param {
                 result = AST::MethodType::Params::Optional.new(location: val[0].first,
                                                                type: val[0].last)
              }
            | optional_param COMMA block_params1 {
                loc = val.first[0] + (val[2] || val[1]).location
                type = val.first[1]
                next_params = val[2]
                result = AST::MethodType::Params::Optional.new(location: loc, type: type, next_params: next_params)
              }
            | block_params2 { result = val[0] }

block_params2: { result = nil }
             | rest_param {
                 result = AST::MethodType::Params::Rest.new(location: val[0].first, type: val[0].last)
               }

simple_type: type_name {
        result = AST::Types::Name.new(name: val[0].value, location: val[0].location, args: [])
      }
    | instance_type_name LT type_seq GT {
        loc = val[0].location + val[3].location
        name = val[0].value
        args = val[2]
        result = AST::Types::Name.new(location: loc, name: name, args: args)
      }
    | ANY { result = AST::Types::Any.new(location: val[0].location) }
    | TVAR { result = AST::Types::Var.new(location: val[0].location, name: val[0].value) }
    | CLASS { result = AST::Types::Class.new(location: val[0].location) }
    | MODULE { result = AST::Types::Class.new(location: val[0].location) }
    | INSTANCE { result = AST::Types::Instance.new(location: val[0].location) }
    | SELF { result = AST::Types::Self.new(location: val[0].location) }
    | VOID { result = AST::Types::Void.new(location: val[0].location) }
    | NIL { result = AST::Types::Nil.new(location: val[0].location) }
    | BOOL { result = AST::Types::Boolean.new(location: val[0].location) }
    | simple_type QUESTION {
        type = val[0]
        nil_type = AST::Types::Nil.new(location: val[1].location)
        result = AST::Types::Union.build(types: [type, nil_type], location: val[0].location + val[1].location)
      }
    | SELFQ {
        type = AST::Types::Self.new(location: val[0].location)
        nil_type = AST::Types::Nil.new(location: val[0].location)
        result = AST::Types::Union.build(types: [type, nil_type], location: val[0].location)
      }
    | INT { result = AST::Types::Literal.new(value: val[0].value, location: val[0].location) }
    | STRING { result = AST::Types::Literal.new(value: val[0].value, location: val[0].location) }
    | SYMBOL { result = AST::Types::Literal.new(value: val[0].value, location: val[0].location) }
    | LBRACKET type_seq RBRACKET {
        loc = val[0].location + val[2].location
        result = AST::Types::Tuple.new(types: val[1], location: loc)
      }

paren_type: LPAREN type RPAREN { result = val[1].with_location(val[0].location + val[2].location) }
          | simple_type

instance_type_name: module_name {
                      result = LocatedValue.new(value: TypeName::Instance.new(name: val[0].value),
                                                location: val[0].location)
                    }
                  | INTERFACE_NAME {
                      result = LocatedValue.new(value: TypeName::Interface.new(name: val[0].value),
                                                location: val[0].location)
                    }

type_name: instance_type_name
         | module_name DOT CLASS constructor {
             loc = val[0].location + (val[3] || val[2]).location
             result = LocatedValue.new(value: TypeName::Class.new(name: val[0].value, constructor: val[3]&.value),
                                       location: loc)
           }
         | module_name DOT MODULE {
             loc = val[0].location + val.last.location
             result = LocatedValue.new(value: TypeName::Module.new(name: val[0].value),
                                       location: loc)
           }

constructor: { result = nil }
           | CONSTRUCTOR
           | NOCONSTRUCTOR

type: paren_type
    | union_seq {
        loc = val[0].first.location + val[0].last.location
        result = AST::Types::Union.build(types: val[0], location: loc)
      }

type_seq: type { result = [val[0]] }
        | type COMMA type_seq { result = [val[0]] + val[2] }

union_seq: simple_type BAR simple_type { result = [val[0], val[2]] }
         | simple_type BAR union_seq { result = [val[0]] + val[2] }

keyword: IDENT
       | MODULE_NAME
       | INTERFACE_NAME
       | ANY
       | CLASS
       | MODULE
       | INSTANCE
       | BLOCK
       | INCLUDE
       | IVAR
       | SELF

signatures: { result = [] }
          | interface signatures { result = [val[0]] + val[1] }
          | class_decl signatures { result = [val[0]] + val[1] }
          | module_decl signatures { result = [val[0]] + val[1] }
          | extension_decl signatures { result = [val[0]] + val[1] }
          | const_decl signatures { result = [val[0]] + val[1] }
          | gvar_decl signatures { result = [val[0]] + val[1] }

gvar_decl: GVAR COLON type {
             loc = val.first.location + val.last.location
             result = AST::Signature::Gvar.new(
               location: loc,
               name: val[0].value,
               type: val[2]
             )
           }

const_decl: module_name COLON type {
              loc = val.first.location + val.last.location
              result = AST::Signature::Const.new(
                location: loc,
                name: val[0].value,
                type: val[2]
              )
            }

interface: INTERFACE interface_name type_params interface_members END {
             loc = val.first.location + val.last.location
             result = AST::Signature::Interface.new(
               location: loc,
               name: val[1].value,
               params: val[2],
               methods: val[3]
             )
           }

class_decl: CLASS module_name type_params super_opt class_members END {
              loc = val.first.location + val.last.location
              result = AST::Signature::Class.new(name: val[1].value.absolute!,
                                                 params: val[2],
                                                 super_class: val[3],
                                                 members: val[4],
                                                 location: loc)
            }
module_decl: MODULE module_name type_params self_type_opt class_members END {
               loc = val.first.location + val.last.location
               result = AST::Signature::Module.new(name: val[1].value.absolute!,
                                                   location: loc,
                                                   params: val[2],
                                                   self_type: val[3],
                                                   members: val[4])
             }
extension_decl: EXTENSION module_name type_params LPAREN UIDENT RPAREN class_members END {
                  loc = val.first.location + val.last.location
                  result = AST::Signature::Extension.new(module_name: val[1].value.absolute!,
                                                         name: val[4].value,
                                                         location: loc,
                                                         params: val[2],
                                                         members: val[6])
                }

self_type_opt: { result = nil }
             | COLON type { result = val[1] }

interface_name: INTERFACE_NAME

module_name: module_name0
           | COLON2 module_name0 {
               loc = val.first.location + val.last.location
               result = LocatedValue.new(location: loc, value: val[1].value.absolute!)
             }

module_name0: UIDENT {
                result = LocatedValue.new(location: val[0].location, value: ModuleName.parse(val[0].value))
              }
           | UIDENT COLON2 module_name0 {
               location = val[0].location + val.last.location
               name = ModuleName.parse(val[0].value) + val.last.value
               result = LocatedValue.new(location: location, value: name)
             }

class_members: { result = [] }
             | class_member class_members { result = [val[0]] + val[1] }

class_member: instance_method_member
            | module_method_member
            | module_instance_method_member
            | include_member
            | extend_member
            | ivar_member
            | attr_reader_member
            | attr_accessor_member

ivar_member: IVAR_NAME COLON type {
               loc = val.first.location + val.last.location
               result = AST::Signature::Members::Ivar.new(
                 location: loc,
                 name: val[0].value,
                 type: val[2]
               )
             }

instance_method_member: DEF constructor_method method_name COLON method_type_union {
                          loc = val.first.location + val.last.last.location
                          result = AST::Signature::Members::Method.new(
                            name: val[2].value,
                            types: val[4],
                            kind: :instance,
                            location: loc,
                            attributes: [val[1] ? :constructor : nil].compact
                          )
                        }
module_method_member: DEF constructor_method SELF DOT method_name COLON method_type_union {
                        loc = val.first.location + val.last.last.location
                        result = AST::Signature::Members::Method.new(
                          name: val[4].value,
                          types: val[6],
                          kind: :module,
                          location: loc,
                          attributes: [val[1] ? :constructor : nil].compact
                        )
                      }
module_instance_method_member: DEF constructor_method SELFQ DOT method_name COLON method_type_union {
                                 loc = val.first.location + val.last.last.location
                                 result = AST::Signature::Members::Method.new(
                                   name: val[4].value,
                                   types: val[6],
                                   kind: :module_instance,
                                   location: loc,
                                   attributes: [val[1] ? :constructor : nil].compact
                                 )
                               }
include_member: INCLUDE module_name {
                  loc = val.first.location + val.last.location
                  name = val[1].value
                  result = AST::Signature::Members::Include.new(name: name, location: loc, args: [])
                }
              | INCLUDE module_name LT type_seq GT {
                  loc = val.first.location + val.last.location
                  name = val[1].value
                  result = AST::Signature::Members::Include.new(name: name, location: loc, args: val[3])
                }
extend_member: EXTEND module_name {
                 loc = val.first.location + val.last.location
                 name = val[1].value
                 result = AST::Signature::Members::Extend.new(name: name, location: loc, args: [])
               }
             | EXTEND module_name LT type_seq GT {
                 loc = val.first.location + val.last.location
                 name = val[1].value
                 result = AST::Signature::Members::Extend.new(name: name, location: loc, args: val[3])
               }
attr_reader_member: ATTR_READER method_name attr_ivar_opt COLON type {
                      loc = val.first.location + val.last.location
                      result = AST::Signature::Members::Attr.new(location: loc, name: val[1].value, kind: :reader, ivar: val[2], type: val[4])
                    }
attr_accessor_member: ATTR_ACCESSOR method_name attr_ivar_opt COLON type {
                        loc = val.first.location + val.last.location
                        result = AST::Signature::Members::Attr.new(location: loc, name: val[1].value, kind: :accessor, ivar: val[2], type: val[4])
                      }

attr_ivar_opt: { result = nil }
             | LPAREN RPAREN { result = false }
             | LPAREN IVAR_NAME RPAREN { result = val[1].value }

constructor_method: { result = false }
                  | LPAREN CONSTRUCTOR RPAREN { result = true }

super_opt: { result = nil }
         | LTCOLON super_class { result = val[1] }

super_class: module_name {
               result = AST::Signature::SuperClass.new(location: val[0].location, name: val[0].value, args: [])
             }
           | module_name LT type_seq GT {
               loc = val[0].location + val[3].location
               name = val[0].value
               result = AST::Signature::SuperClass.new(location: loc, name: name, args: val[2])
             }

type_params: { result = nil }
           | LT type_param_seq GT {
              location = val[0].location + val[2].location
              result = AST::TypeParams.new(location: location, variables: val[1])
            }

type_param_seq: TVAR { result = [val[0].value] }
           | TVAR COMMA type_param_seq { result = [val[0].value] + val[2] }

interface_members: { result = [] }
           | interface_method interface_members { result = val[1].unshift(val[0]) }

interface_method: DEF method_name COLON method_type_union {
                    loc = val[0].location + val[3].last.location
                    result = AST::Signature::Interface::Method.new(location: loc, name: val[1].value, types: val[3])
                  }

method_type_union: method_type { result = [val[0]] }
                 | method_type BAR method_type_union { result = [val[0]] + val[2] }

method_name: method_name0
           | STAR | STAR2
           | PERCENT | MINUS
           | LT | GT
           | BAR { result = LocatedValue.new(location: val[0].location, value: :|) }
           | method_name0 EQ {
               raise ParseError, "\nunexpected method name #{val[0].to_s} =" unless val[0].location.pred?(val[1].location)
               result = LocatedValue.new(location: val[0].location + val[1].location,
                                         value: :"#{val[0].value}=")
             }
           | method_name0 QUESTION {
               raise ParseError, "\nunexpected method name #{val[0].to_s} ?" unless val[0].location.pred?(val[1].location)
               result = LocatedValue.new(location: val[0].location + val[1].location,
                                         value: :"#{val[0].value}?")
           }
           | method_name0 BANG {
               raise ParseError, "\nunexpected method name #{val[0].to_s} !" unless val[0].location.pred?(val[1].location)
               result = LocatedValue.new(location: val[0].location + val[1].location,
                                         value: :"#{val[0].value}!")
           }
           | GT GT {
               raise ParseError, "\nunexpected method name > >" unless val[0].location.pred?(val[1].location)
               result = LocatedValue.new(location: val[0].location + val[1].location, value: :>>)
             }

method_name0: IDENT
            | UIDENT
            | MODULE_NAME
            | INTERFACE_NAME
            | ANY | VOID
            | INTERFACE
            | END
            | PLUS
            | CLASS
            | MODULE
            | INSTANCE
            | EXTEND
            | INCLUDE
            | OPERATOR
            | BANG
            | BLOCK
            | BREAK
            | METHOD
            | BOOL
            | CONSTRUCTOR { result = LocatedValue.new(location: val[0].location, value: :constructor) }
            | NOCONSTRUCTOR { result = LocatedValue.new(location: val[0].location, value: :noconstructor) }
            | ATTR_READER
            | ATTR_ACCESSOR

annotation: AT_TYPE VAR subject COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::VarType.new(location: loc,
                                                    name: val[2].value,
                                                    type: val[4])
            }
          | AT_TYPE METHOD subject COLON method_type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::MethodType.new(location: loc,
                                                       name: val[2].value,
                                                       type: val[4])
            }
          | AT_TYPE RETURN COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::ReturnType.new(type: val[3], location: loc)
            }
          | AT_TYPE BLOCK COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::BlockType.new(type: val[3], location: loc)
            }
          | AT_TYPE SELF COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::SelfType.new(type: val[3], location: loc)
            }
          | AT_TYPE CONST module_name COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::ConstType.new(name: val[2].value,
                                                      type: val[4],
                                                      location: loc)
            }
          | AT_TYPE INSTANCE COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::InstanceType.new(type: val[3], location: loc)
            }
          | AT_TYPE MODULE COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::ModuleType.new(type: val[3], location: loc)
            }
          | AT_TYPE IVAR IVAR_NAME COLON type {
              loc = val.first.location + val.last.location
              result = AST::Annotation::IvarType.new(name: val[2].value, type: val[4], location: loc)
            }
          | AT_IMPLEMENTS module_name type_params {
              loc = val[0].location + (val[2]&.location || val[1].location)
              args = val[2]&.variables || []
              name = AST::Annotation::Implements::Module.new(name: val[1].value, args: args)
              result = AST::Annotation::Implements.new(name: name, location: loc)
            }
          | AT_DYNAMIC dynamic_names {
             loc = val[0].location + val[1].last.location
             result = AST::Annotation::Dynamic.new(names: val[1], location: loc)
           }
          | AT_TYPE BREAK COLON type {
             loc = val.first.location + val.last.location
             result = AST::Annotation::BreakType.new(type: val[3], location: loc)
           }

dynamic_names: dynamic_name COMMA dynamic_names { result = [val[0]] + val[2] }
             | dynamic_name { result = val }

dynamic_name: method_name {
             result = AST::Annotation::Dynamic::Name.new(name: val[0].value, location: val[0].location, kind: :instance)
           }
           | SELF DOT method_name {
             loc = val.first.location + val.last.location
             result = AST::Annotation::Dynamic::Name.new(name: val[2].value, location: loc, kind: :module)
           }
           | SELFQ DOT method_name {
             loc = val.first.location + val.last.location
             result = AST::Annotation::Dynamic::Name.new(name: val[2].value, location: loc, kind: :module_instance)
           }

subject: IDENT { result = val[0] }

end

---- inner

require "strscan"

attr_reader :input
attr_reader :buffer
attr_reader :offset

def initialize(type, buffer:, offset:, input: nil)
  super()
  @type = type
  @buffer = buffer
  @input = StringScanner.new(input || buffer.content)
  @offset = offset
end

def self.parse_method(input, name: nil)
  new(:METHOD, buffer: AST::Buffer.new(name: name, content: input), offset: 0).do_parse
end

def self.parse_signature(input, name: nil)
  new(:SIGNATURE, buffer: AST::Buffer.new(name: name, content: input), offset: 0).do_parse
end

def self.parse_annotation_opt(input, buffer:, offset: 0)
  new(:ANNOTATION, input: input, buffer: buffer, offset: offset).do_parse
rescue => exn
  Steep.logger.debug "Parsing comment failed: #{exn.inspect}"
  nil
end

def self.parse_type(input, name: nil)
  new(:TYPE, buffer: AST::Buffer.new(name: name, content: input), offset: 0).do_parse
end

class LocatedValue
  attr_reader :location
  attr_reader :value

  def initialize(location:, value:)
    @location = location
    @value = value
  end
end

def new_token(type, value = nil)
  start_index = offset + input.pos - input.matched.bytesize
  end_index = offset + input.pos

  location = AST::Location.new(buffer: buffer,
                               start_pos: start_index,
                               end_pos: end_index)

  [type, LocatedValue.new(location: location, value: value)]
end

def next_token
  if @type
    type = @type
    @type = nil
    return [:"type_#{type}", nil]
  end

  case
  when input.scan(/\s+/)
    next_token
  when input.scan(/#.*/)
    next_token
  when input.eos?
    [false, false]
  when input.scan(/->/)
    new_token(:ARROW)
  when input.scan(/\?/)
    new_token(:QUESTION)
  when input.scan(/!/)
    new_token(:BANG)
  when input.scan(/\(/)
    new_token(:LPAREN, nil)
  when input.scan(/\)/)
    new_token(:RPAREN, nil)
  when input.scan(/{/)
    new_token(:LBRACE, nil)
  when input.scan(/}/)
    new_token(:RBRACE, nil)
  when input.scan(/,/)
    new_token(:COMMA, nil)
  when input.scan(/:\w+/)
    new_token(:SYMBOL, input.matched[1..-1].to_sym)
  when input.scan(/::/)
    new_token(:COLON2)
  when input.scan(/:/)
    new_token(:COLON)
  when input.scan(/\*\*/)
    new_token(:STAR2, :**)
  when input.scan(/\*/)
    new_token(:STAR, :*)
  when input.scan(/\+/)
    new_token(:PLUS, :+)
  when input.scan(/\./)
    new_token(:DOT)
  when input.scan(/<:/)
    new_token(:LTCOLON)
  when input.scan(/(\[\]=)|(\[\])|===|==|\^|!=|<</)
    new_token(:OPERATOR, input.matched.to_sym)
  when input.scan(/\[/)
    new_token(:LBRACKET, nil)
  when input.scan(/\]/)
    new_token(:RBRACKET, nil)
  when input.scan(/<=/)
    new_token(:OPERATOR, :<=)
  when input.scan(/>=/)
    new_token(:OPERATOR, :>=)
  when input.scan(/=/)
    new_token(:EQ, :"=")
  when input.scan(/</)
    new_token(:LT, :<)
  when input.scan(/>/)
    new_token(:GT, :>)
  when input.scan(/nil\b/)
    new_token(:NIL, :nil)
  when input.scan(/bool\b/)
    new_token(:BOOL, :bool)
  when input.scan(/any\b/)
    new_token(:ANY, :any)
  when input.scan(/void\b/)
    new_token(:VOID, :void)
  when input.scan(/interface\b/)
    new_token(:INTERFACE, :interface)
  when input.scan(/end\b/)
    new_token(:END, :end)
  when input.scan(/\|/)
    new_token(:BAR, :bar)
  when input.scan(/def\b/)
    new_token(:DEF)
  when input.scan(/@type\b/)
    new_token(:AT_TYPE)
  when input.scan(/@implements\b/)
    new_token(:AT_IMPLEMENTS)
  when input.scan(/@dynamic\b/)
    new_token(:AT_DYNAMIC)
  when input.scan(/const\b/)
    new_token(:CONST, :const)
  when input.scan(/var\b/)
    new_token(:VAR, :var)
  when input.scan(/return\b/)
    new_token(:RETURN)
  when input.scan(/block\b/)
    new_token(:BLOCK, :block)
  when input.scan(/break\b/)
    new_token(:BREAK, :break)
  when input.scan(/method\b/)
    new_token(:METHOD, :method)
  when input.scan(/self\?/)
    new_token(:SELFQ)
  when input.scan(/self\b/)
    new_token(:SELF, :self)
  when input.scan(/'\w+/)
    new_token(:TVAR, input.matched.gsub(/\A'/, '').to_sym)
  when input.scan(/attr_reader\b/)
    new_token(:ATTR_READER, :attr_reader)
  when input.scan(/attr_accessor\b/)
    new_token(:ATTR_ACCESSOR, :attr_accessor)
  when input.scan(/instance\b/)
    new_token(:INSTANCE, :instance)
  when input.scan(/class\b/)
    new_token(:CLASS, :class)
  when input.scan(/module\b/)
    new_token(:MODULE, :module)
  when input.scan(/include\b/)
    new_token(:INCLUDE, :include)
  when input.scan(/extend\b/)
    new_token(:EXTEND, :extend)
  when input.scan(/instance\b/)
    new_token(:INSTANCE, :instance)
  when input.scan(/ivar\b/)
    new_token(:IVAR, :ivar)
  when input.scan(/%/)
    new_token(:PERCENT, :%)
  when input.scan(/-/)
    new_token(:MINUS, :-)
  when input.scan(/&/)
    new_token(:OPERATOR, :&)
  when input.scan(/~/)
    new_token(:OPERATOR, :~)
  when input.scan(/\//)
    new_token(:OPERATOR, :/)
  when input.scan(/extension\b/)
    new_token(:EXTENSION, :extension)
  when input.scan(/constructor\b/)
    new_token(:CONSTRUCTOR, true)
  when input.scan(/noconstructor\b/)
    new_token(:NOCONSTRUCTOR, false)
  when input.scan(/\$\w+\b/)
    new_token(:GVAR, input.matched.to_sym)
  when input.scan(/[A-Z]\w*/)
    new_token(:UIDENT, input.matched.to_sym)
  when input.scan(/_\w+/)
    new_token(:INTERFACE_NAME, input.matched.to_sym)
  when input.scan(/@\w+/)
    new_token(:IVAR_NAME, input.matched.to_sym)
  when input.scan(/\d+/)
    new_token(:INT, input.matched.to_i)
  when input.scan(/\"[^\"]*\"/)
    new_token(:STRING, input.matched[1...-1])
  when input.scan(/\w+/)
    new_token(:IDENT, input.matched.to_sym)
  end
end
