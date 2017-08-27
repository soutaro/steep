class Steep::Parser

rule

target: type_METHOD method_type { result = val[1] }
      | type_SIGNATURE signatures { result = val[1] }
      | type_ANNOTATION annotation { result = val[1] }

method_type: type_params params block_opt ARROW return_type
               { result = Interface::MethodType.new(type_params: val[0], params: val[1], block: val[2], return_type: val[4]) }

return_type: simple_type
           | LPAREN union_seq RPAREN { result = Types::Union.new(types: val[1]) }

params: { result = Interface::Params.empty }
      | LPAREN params0 RPAREN { result = val[1] }
      | type { result = Interface::Params.empty.with(required: [val[0]]) }

params0: required_param { result = Interface::Params.empty.with(required: [val[0]]) }
       | required_param COMMA params0 { result = val[2].with(required: [val[0]] + val[2].required) }
       | params1 { result = val[0] }

params1: optional_param { result = Interface::Params.empty.with(optional: [val[0]]) }
       | optional_param COMMA params1 { result = val[2].with(optional: [val[0]] + val[2].optional) }
       | params2 { result = val[0] }

params2: rest_param { result = Interface::Params.empty.with(rest: val[0]) }
       | rest_param COMMA params3 { result = val[2].with(rest: val[0]) }
       | params3 { result = val[0] }

params3: required_keyword { result = Interface::Params.empty.with(required_keywords: val[0]) }
       | optional_keyword { result = Interface::Params.empty.with(optional_keywords: val[0]) }
       | required_keyword COMMA params3 { result = val[2].with(required_keywords: val[2].required_keywords.merge(val[0])) }
       | optional_keyword COMMA params3 { result = val[2].with(optional_keywords: val[2].optional_keywords.merge(val[0])) }
       | params4 { result = val[0] }

params4: { result = Interface::Params.empty }
       | STAR2 type { result = Interface::Params.empty.with(rest_keywords: val[1]) }

required_param: type { result = val[0] }
optional_param: QUESTION type { result = val[1] }
rest_param: STAR type { result = val[1] }
required_keyword: keyword COLON type { result = { val[0] => val[2] } }
optional_keyword: QUESTION keyword COLON type { result = { val[1] => val[3] } }

block_opt: { result = nil }
         | LBRACE RBRACE { result = Interface::Block.new(params: Interface::Params.empty.with(rest: Types::Any.new),
                                                                return_type: Types::Any.new) }
         | LBRACE block_params ARROW type RBRACE { result = Interface::Block.new(params: val[1], return_type: val[3]) }

block_params: LPAREN block_params0 RPAREN { result = val[1] }
            | { result = Interface::Params.empty.with(rest: Types::Any.new) }

block_params0: required_param { result = Interface::Params.empty.with(required: [val[0]]) }
             | required_param COMMA block_params0 { result = val[2].with(required: [val[0]] + val[2].required) }
             | block_params1 { result = val[0] }

block_params1: optional_param { result = Interface::Params.empty.with(optional: [val[0]]) }
            | optional_param COMMA block_params1 { result = val[2].with(optional: [val[0]] + val[2].optional) }
            | block_params2 { result = val[0] }

block_params2: { result = Interface::Params.empty }
             | rest_param { result = Interface::Params.empty.with(rest: val[0]) }

simple_type: INTERFACE_NAME { result = Types::Name.interface(name: val[0]) }
    | INTERFACE_NAME LT type_seq GT { result = Types::Name.interface(name: val[0], params: val[2]) }
    | MODULE_NAME { result = Types::Name.instance(name: val[0])}
    | MODULE_NAME LT type_seq GT { result = Types::Name.instance(name: val[0], params: val[2]) }
    | CLASS_IDENT { result = Types::Name.module(name: val[0]) }
    | ANY { result = Types::Any.new }
    | TVAR { result = Types::Var.new(name: val[0]) }
    | CLASS { result = Types::Class.new }
    | MODULE { result = Types::Class.new }
    | INSTANCE { result = Types::Instance.new }

type: simple_type
    | union_seq { result = Types::Union.new(types: val[0]) }

type_seq: type { result = [val[0]] }
        | type COMMA type_seq { result = [val[0]] + val[2] }

union_seq: simple_type BAR simple_type { result = [val[0], val[2]] }
         | simple_type BAR union_seq { result = [val[0]] + val[2] }

keyword: IDENT
       | MODULE_NAME
       | INTERFACE_NAME
       | ANY { result = :any }
       | CLASS { result = :class }
       | MODULE { result = :module }
       | INSTANCE { result = :instance }

signatures: { result = [] }
          | interface signatures { result = [val[0]] + val[1] }
          | class_decl signatures { result = [val[0]] + val[1] }
          | module_decl signatures { result = [val[0]] + val[1] }

interface: INTERFACE interface_name type_params method_decls END { result = Signature::Interface.new(name: val[1], params: val[2], methods: val[3]) }
class_decl: CLASS class_name type_params super_opt class_members END { result = Signature::Class.new(name: val[1], params: val[2], super_class: val[3], members: val[4] )}
module_decl: MODULE class_name type_params self_type_opt class_members END { result = Signature::Module.new(name: val[1], params: val[2], self_type: val[3], members: val[4]) }

self_type_opt: { result = nil }
             | COLON type { result = val[1] }

interface_name: INTERFACE_NAME { result = val[0] }

class_name: MODULE_NAME { result = val[0] }

class_members: { result = [] }
             | class_member class_members { result = [val[0]] + val[1] }

class_member: instance_method_member { result = val[0] }
            | class_method_member { result = val[0] }
            | class_instance_method_member { result = val[0] }
            | include_member { result = val[0] }
            | extend_member { result = val[0] }

instance_method_member: DEF method_name COLON method_type_union { result = Signature::Members::InstanceMethod.new(name: val[1], types: val[3]) }
class_method_member: DEF SELF DOT method_name COLON method_type_union { result = Signature::Members::ModuleMethod.new(name: val[3], types: val[5]) }
class_instance_method_member: DEF SELFQ DOT method_name COLON method_type_union { result = Signature::Members::ModuleInstanceMethod.new(name: val[3], types: val[5]) }
include_member: INCLUDE type { result = Signature::Members::Include.new(name: val[1]) }
extend_member: EXTEND type { result = Signature::Members::Extend.new(name: val[1]) }

super_opt: { result = nil }
         | LTCOLON type { result = val[1] }

type_params: { result = [] }
          | LT type_param_seq GT { result = val[1] }

type_param_seq: TVAR { result = [val[0]] }
           | TVAR COMMA type_param_seq { result = [val[0]] + val[2] }

method_decls: { result = {} }
            | method_decl method_decls { result = val[1].merge(val[0]) }

method_decl: DEF method_name COLON method_type_union { result = { val[1] => val[3] }}

method_type_union: method_type { result = [val[0]] }
                 | method_type BAR method_type_union { result = [val[0]] + val[2] }

method_name: IDENT
           | MODULE_NAME
           | INTERFACE_NAME
           | ANY { result = :any }
           | INTERFACE { result = :interface }
           | END { result = :end }
           | PLUS { result = :+ }
           | CLASS { result = :class }
           | MODULE { result = :module }
           | INSTANCE { result = :instance }

annotation: AT_TYPE VAR subject COLON type { result = Annotation::VarType.new(var: val[2], type: val[4]) }
          | AT_TYPE METHOD subject COLON method_type { result = Annotation::MethodType.new(method: val[2], type: val[4]) }
          | AT_TYPE RETURN COLON type { result = Annotation::ReturnType.new(type: val[3]) }
          | AT_TYPE BLOCK COLON type { result = Annotation::BlockType.new(type: val[3]) }
          | AT_TYPE SELF COLON type { result = Annotation::SelfType.new(type: val[3]) }
          | AT_TYPE CONST CONST_PATH COLON type { result = Annotation::ConstType.new(name: val[2], type: val[4]) }
          | AT_TYPE CONST MODULE_NAME COLON type { result = Annotation::ConstType.new(name: val[2], type: val[4]) }
          | AT_TYPE INSTANCE COLON type { result = Annotation::InstanceType.new(type: val[3]) }
          | AT_TYPE MODULE COLON type { result = Annotation::ModuleType.new(type: val[3]) }
          | AT_TYPE { raise "Invalid type annotation" }

subject: IDENT { result = val[0] }

end

---- inner

require "strscan"

attr_reader :input

def initialize(type, input)
  super()
  @type = type
  @input = StringScanner.new(input)
end

def self.parse_method(input)
  new(:METHOD, input).do_parse
end

def self.parse_signature(input)
  new(:SIGNATURE, input).do_parse
end

def self.parse_annotation_opt(input)
  new(:ANNOTATION, input).do_parse
rescue
  nil
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
    [:ARROW, nil]
  when input.scan(/\?/)
    [:QUESTION, nil]
  when input.scan(/\(/)
    [:LPAREN, nil]
  when input.scan(/\)/)
    [:RPAREN, nil]
  when input.scan(/{/)
    [:LBRACE, nil]
  when input.scan(/}/)
    [:RBRACE, nil]
  when input.scan(/,/)
    [:COMMA, nil]
  when input.scan(/[A-Z]\w*(::[A-Z]\w*)+/)
    [:CONST_PATH, input.matched.to_sym]
  when input.scan(/::[A-Z]\w*(::[A-Z]\w*)*/)
    [:CONST_PATH, input.matched.to_sym]
  when input.scan(/:/)
    [:COLON, nil]
  when input.scan(/\*\*/)
    [:STAR2, nil]
  when input.scan(/\*/)
    [:STAR, nil]
  when input.scan(/\+/)
    [:PLUS, nil]
  when input.scan(/<:/)
    [:LTCOLON, nil]
  when input.scan(/</)
    [:LT, nil]
  when input.scan(/>/)
    [:GT, nil]
  when input.scan(/\./)
    [:DOT, nil]
  when input.scan(/any/)
    [:ANY, nil]
  when input.scan(/interface/)
    [:INTERFACE, nil]
  when input.scan(/end/)
    [:END, nil]
  when input.scan(/\|/)
    [:BAR, nil]
  when input.scan(/def/)
    [:DEF, nil]
  when input.scan(/@type/)
    [:AT_TYPE, nil]
  when input.scan(/const/)
    [:CONST, nil]
  when input.scan(/var/)
    [:VAR, nil]
  when input.scan(/return/)
    [:RETURN, nil]
  when input.scan(/block/)
    [:BLOCK, nil]
  when input.scan(/method/)
    [:METHOD, nil]
  when input.scan(/self\?/)
    [:SELFQ, nil]
  when input.scan(/self/)
    [:SELF, nil]
  when input.scan(/'\w+/)
    [:TVAR, input.matched.gsub(/\A'/, '').to_sym]
  when input.scan(/instance/)
    [:INSTANCE, nil]
  when input.scan(/class/)
    [:CLASS, nil]
  when input.scan(/module/)
    [:MODULE, nil]
  when input.scan(/include/)
    [:INCLUDE, nil]
  when input.scan(/extend/)
    [:EXTEND, nil]
  when input.scan(/[A-Z]\w*\.(class|module)\b/)
    [:CLASS_IDENT, input.matched.gsub(/\.(class|module)$/, '').to_sym]
  when input.scan(/[A-Z]\w*/)
    [:MODULE_NAME, input.matched.to_sym]
  when input.scan(/_\w+/)
    [:INTERFACE_NAME, input.matched.to_sym]
  when input.scan(/\w+/)
    [:IDENT, input.matched.to_sym]
  end
end
