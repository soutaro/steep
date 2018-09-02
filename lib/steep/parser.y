class Steep::Parser

token kCLASS kMODULE kINTERFACE kDEF kEND kNIL kBOOL kANY kVOID kTYPE
      kINCOMPATIBLE kAT_TYPE kAT_IMPLEMENTS kAT_DYNAMIC kCONST kVAR kRETURN
      kBLOCK kBREAK kMETHOD kSELF kSELFQ kATTR_READER kATTR_ACCESSOR kINSTANCE
      kINCLUDE kEXTEND kINSTANCE kIVAR kCONSTRUCTOR kNOCONSTRUCTOR kEXTENSION
      tARROW tBANG tBAR tCOLON tCOLON2 tCOMMA tDOT tEQ tGT tGVAR tHAT tINT
      tINTERFACE_NAME tIVAR_NAME tLBRACE tLBRACKET tIDENT tLPAREN tLT
      tLTCOLON tMINUS tOPERATOR tPERCENT tPLUS tQUESTION tRBRACE tRBRACKET
      tRPAREN tSTAR tSTAR2 tSTRING tSYMBOL tUIDENT tUMINUS tVAR
      type_METHOD type_SIGNATURE type_ANNOTATION type_TYPE

expect 1

rule

                        target: type_METHOD method_type
                                {
                                  result = val[1]
                                }
                              | type_SIGNATURE signatures
                                {
                                  result = val[1]
                                }
                              | type_ANNOTATION annotation
                                {
                                  result = val[1]
                                }
                              | type_TYPE type
                                {
                                  result = val[1]
                                }

                   method_type: type_params params block_opt tARROW return_type
                                {
                                  result = AST::MethodType.new(location: AST::Location.concat(*val.compact.map(&:location)),
                                                               type_params: val[0],
                                                               params: val[1]&.value,
                                                               block: val[2],
                                                               return_type: val[4])
                                }

                   return_type: paren_type

                        params: # nothing
                                {
                                  result = nil
                                }
                              | tLPAREN params0 tRPAREN
                                {
                                  result = LocatedValue.new(location: val[0].location + val[2].location,
                                                            value: val[1])
                                }
                              | simple_type
                                {
                                  result = LocatedValue.new(location: val[0].location,
                                                            value: AST::MethodType::Params::Required.new(location: val[0].location, type: val[0]))
                                }

                       params0: required_param
                                {
                                  result = AST::MethodType::Params::Required.new(location: val[0].location, type: val[0])
                                }
                              | required_param tCOMMA params0
                                {
                                  location = val[0].location
                                  result = AST::MethodType::Params::Required.new(location: location,
                                                                                 type: val[0],
                                                                                 next_params: val[2])
                                }
                              | params1
                                {
                                  result = val[0]
                                }

                       params1: optional_param
                                {
                                  result = AST::MethodType::Params::Optional.new(location: val[0].first, type: val[0].last)
                                }
                              | optional_param tCOMMA params1
                                {
                                  location = val[0].first
                                  result = AST::MethodType::Params::Optional.new(type: val[0].last, location: location, next_params: val[2])
                                }
                              | params2
                                {
                                  result = val[0]
                                }

                       params2: rest_param
                                {
                                  result = AST::MethodType::Params::Rest.new(location: val[0].first, type: val[0].last)
                                }
                              | rest_param tCOMMA params3
                                {
                                  loc = val[0].first
                                  result = AST::MethodType::Params::Rest.new(location: loc, type: val[0].last, next_params: val[2])
                                }
                              | params3
                                {
                                  result = val[0]
                                }

                       params3: required_keyword
                                {
                                  location, name, type = val[0]
                                  result = AST::MethodType::Params::RequiredKeyword.new(location: location, name: name, type: type)
                                }
                              | optional_keyword
                                {
                                  location, name, type = val[0]
                                  result = AST::MethodType::Params::OptionalKeyword.new(location: location, name: name, type: type)
                                }
                              | required_keyword tCOMMA params3
                                {
                                  location, name, type = val[0]
                                  result = AST::MethodType::Params::RequiredKeyword.new(location: location,
                                                                                        name: name,
                                                                                        type: type,
                                                                                        next_params: val[2])
                                }
                              | optional_keyword tCOMMA params3
                                {
                                  location, name, type = val[0]
                                  result = AST::MethodType::Params::OptionalKeyword.new(location: location,
                                                                                        name: name,
                                                                                        type: type,
                                                                                        next_params: val[2])
                                }
                              | params4
                                {
                                  result = val[0]
                                }

                       params4: # nothing
                                {
                                  result = nil
                                }
                              | tSTAR2 type
                                {
                                  result = AST::MethodType::Params::RestKeyword.new(location: val[0].location + val[1].location,
                                                                                    type: val[1])
                                }

                required_param: type
                                {
                                  result = val[0]
                                }

                optional_param: tQUESTION type
                                {
                                  result = [
                                    val[0].location + val[1].location,
                                    val[1]
                                  ]
                                }

                    rest_param: tSTAR type
                                {
                                  result = [
                                    val[0].location + val[1].location,
                                    val[1]
                                  ]
                                }

              required_keyword: keyword tCOLON type
                                {
                                  result = [
                                    val[0].location + val[2].location,
                                    val[0].value,
                                    val[2]
                                  ]
                                }

              optional_keyword: tQUESTION keyword tCOLON type
                                {
                                  result = [
                                    val[0].location + val[3].location,
                                    val[1].value,
                                    val[3]
                                  ]
                                }

                     block_opt: # nothing
                                {
                                  result = nil
                                }
                              | block_optional tLBRACE tRBRACE
                                {
                                  result = AST::MethodType::Block.new(params: nil,
                                                                      return_type: nil,
                                                                      location: (val[0] || val[1]).location + val[2].location,
                                                                      optional: val[0]&.value || false)
                                }
                              | block_optional tLBRACE block_params tARROW type tRBRACE
                                {
                                  result = AST::MethodType::Block.new(params: val[2],
                                                                      return_type: val[4],
                                                                      location: (val[0] || val[1]).location + val[5].location,
                                                                      optional: val[0]&.value || false)
                                }

                block_optional: # nothing
                                {
                                  result = nil
                                }
                              | tQUESTION
                                {
                                  result = LocatedValue.new(location: val[0].location, value: true)
                                }

                  block_params: # nothing
                                {
                                  result = nil
                                }
                              | tLPAREN block_params0 tRPAREN
                                {
                                  result = val[1]
                                }

                 block_params0: required_param
                                {
                                  result = AST::MethodType::Params::Required.new(location: val[0].location,
                                                                                 type: val[0])
                                }
                              | required_param tCOMMA block_params0 {
                                  result = AST::MethodType::Params::Required.new(location: val[0].location,
                                                                                 type: val[0],
                                                                                 next_params: val[2])
                                }
                              | block_params1
                                {
                                  result = val[0]
                                }

                 block_params1: optional_param
                                {
                                  result = AST::MethodType::Params::Optional.new(location: val[0].first,
                                                                                 type: val[0].last)
                                }
                              | optional_param tCOMMA block_params1
                                {
                                  loc = val.first[0] + (val[2] || val[1]).location
                                  type = val.first[1]
                                  next_params = val[2]
                                  result = AST::MethodType::Params::Optional.new(location: loc, type: type, next_params: next_params)
                                }
                              | block_params2
                                {
                                  result = val[0]
                                }

                 block_params2: # nothing
                                {
                                  result = nil
                                }
                              | rest_param
                                {
                                  result = AST::MethodType::Params::Rest.new(location: val[0].first, type: val[0].last)
                                }

                   simple_type: type_name
                                {
                                  result = AST::Types::Name.new(name: val[0].value, location: val[0].location, args: [])
                                }
                              | application_type_name tLT type_seq tGT
                                {
                                  loc = val[0].location + val[3].location
                                  name = val[0].value
                                  args = val[2]
                                  result = AST::Types::Name.new(location: loc, name: name, args: args)
                                }
                              | kANY
                                {
                                  result = AST::Types::Any.new(location: val[0].location)
                                }
                              | tVAR
                                {
                                  result = AST::Types::Var.new(location: val[0].location, name: val[0].value)
                                }
                              | kCLASS
                                {
                                  result = AST::Types::Class.new(location: val[0].location)
                                }
                              | kMODULE
                                {
                                  result = AST::Types::Class.new(location: val[0].location)
                                }
                              | kINSTANCE
                                {
                                  result = AST::Types::Instance.new(location: val[0].location)
                                }
                              | kSELF
                                {
                                  result = AST::Types::Self.new(location: val[0].location)
                                }
                              | kVOID
                                {
                                  result = AST::Types::Void.new(location: val[0].location)
                                }
                              | kNIL
                                {
                                  result = AST::Types::Nil.new(location: val[0].location)
                                }
                              | kBOOL
                                {
                                  result = AST::Types::Boolean.new(location: val[0].location)
                                }
                              | simple_type tQUESTION
                                {
                                  type = val[0]
                                  nil_type = AST::Types::Nil.new(location: val[1].location)
                                  result = AST::Types::Union.build(types: [type, nil_type], location: val[0].location + val[1].location)
                                }
                              | kSELFQ
                                {
                                  type = AST::Types::Self.new(location: val[0].location)
                                  nil_type = AST::Types::Nil.new(location: val[0].location)
                                  result = AST::Types::Union.build(types: [type, nil_type], location: val[0].location)
                                }
                              | tINT
                                {
                                  result = AST::Types::Literal.new(value: val[0].value, location: val[0].location)
                                }
                              | tSTRING
                                {
                                  result = AST::Types::Literal.new(value: val[0].value, location: val[0].location)
                                }
                              | tSYMBOL
                                {
                                  result = AST::Types::Literal.new(value: val[0].value, location: val[0].location)
                                }
                              | tLBRACKET type_seq tRBRACKET
                                {
                                  loc = val[0].location + val[2].location
                                  result = AST::Types::Tuple.new(types: val[1], location: loc)
                                }

                    paren_type: tLPAREN type tRPAREN
                                {
                                  result = val[1].with_location(val[0].location + val[2].location)
                                }
                              | simple_type

         application_type_name: module_name
                                {
                                  result = LocatedValue.new(value: TypeName::Instance.new(name: val[0].value),
                                                            location: val[0].location)
                                }
                              | tINTERFACE_NAME
                                {
                                  interface_name = InterfaceName.new(name: val[0].value)
                                  result = LocatedValue.new(value: TypeName::Interface.new(name: interface_name),
                                                            location: val[0].location)
                                }
                              | tIDENT
                                {
                                  alias_name = AliasName.new(name: val[0].value)
                                  result = LocatedValue.new(value: TypeName::Alias.new(name: alias_name),
                                                            location: val[0].location)
                                }

                     type_name: application_type_name
                              | module_name tDOT kCLASS constructor
                                {
                                  loc = val[0].location + (val[3] || val[2]).location
                                  result = LocatedValue.new(value: TypeName::Class.new(name: val[0].value, constructor: val[3]&.value),
                                                            location: loc)
                                }
                              | module_name tDOT kMODULE
                                {
                                  loc = val[0].location + val.last.location
                                  result = LocatedValue.new(value: TypeName::Module.new(name: val[0].value),
                                                            location: loc)
                                }

                   constructor: # nothing
                                {
                                  result = nil
                                }
                              | kCONSTRUCTOR
                                {
                                  result = LocatedValue.new(location: val[0].location, value: true)
                                }
                              | kNOCONSTRUCTOR
                                {
                                  result = LocatedValue.new(location: val[0].location, value: false)
                                }

                          type: paren_type
                              | union_seq
                                {
                                  loc = val[0].first.location + val[0].last.location
                                  result = AST::Types::Union.build(types: val[0], location: loc)
                                }
                              | tHAT tLPAREN lambda_params tRPAREN tARROW paren_type
                                {
                                  loc = val[0].location + val[5].location
                                  result = AST::Types::Proc.new(params: val[2], return_type: val[5], location: loc)
                                }

                 lambda_params: lambda_params1
                              | paren_type
                                {
                                  result = Interface::Params.empty.update(required: [val[0]])
                                }
                              | paren_type tCOMMA lambda_params
                                {
                                  result = val[2].update(required: [val[0]] + val[2].required)
                                }

                lambda_params1: # nothing
                                {
                                  result = Interface::Params.empty
                                }
                              | tSTAR paren_type
                                {
                                  result = Interface::Params.empty.update(rest: val[1])
                                }
                              | tQUESTION paren_type
                                {
                                  result = Interface::Params.empty.update(optional: [val[1]])
                                }
                              | tQUESTION paren_type tCOMMA lambda_params1
                                {
                                  result = val[3].update(optional: [val[1]] + val[3].optional)
                                }


                      type_seq: type
                                {
                                  result = [val[0]]
                                }
                              | type tCOMMA type_seq
                                {
                                  result = [val[0]] + val[2]
                                }

                     union_seq: simple_type tBAR simple_type
                                {
                                  result = [val[0], val[2]]
                                }
                              | simple_type tBAR union_seq
                                {
                                  result = [val[0]] + val[2]
                                }

                       keyword: tIDENT
                              | tINTERFACE_NAME
                              | kANY
                              | kCLASS
                              | kMODULE
                              | kINSTANCE
                              | kBLOCK
                              | kINCLUDE
                              | kIVAR
                              | kSELF
                              | kTYPE

                    signatures: # nothing
                                {
                                  result = []
                                }
                              | interface signatures
                                {
                                  result = [val[0]] + val[1]
                                }
                              | class_decl signatures
                                {
                                  result = [val[0]] + val[1]
                                }
                              | module_decl signatures
                                {
                                  result = [val[0]] + val[1]
                                }
                              | extension_decl signatures
                                {
                                  result = [val[0]] + val[1]
                                }
                              | const_decl signatures
                                {
                                  result = [val[0]] + val[1]
                                }
                              | gvar_decl signatures
                                {
                                  result = [val[0]] + val[1]
                                }
                              | alias_decl signatures
                                {
                                  result = [val[0]] + val[1]
                                }

                     gvar_decl: tGVAR tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Gvar.new(
                                    location: loc,
                                    name: val[0].value,
                                    type: val[2]
                                  )
                                }

                    const_decl: module_name tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Const.new(
                                    location: loc,
                                    name: val[0].value.absolute!,
                                    type: val[2]
                                  )
                                }

                     interface: kINTERFACE interface_name type_params interface_members kEND
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Interface.new(
                                    location: loc,
                                    name: val[1].value,
                                    params: val[2],
                                    methods: val[3]
                                  )
                                }

                    class_decl: kCLASS module_name type_params super_opt class_members kEND
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Class.new(name: val[1].value.absolute!,
                                                                     params: val[2],
                                                                     super_class: val[3],
                                                                     members: val[4],
                                                                     location: loc)
                                }

                   module_decl: kMODULE module_name type_params self_type_opt class_members kEND
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Module.new(name: val[1].value.absolute!,
                                                                      location: loc,
                                                                      params: val[2],
                                                                      self_type: val[3],
                                                                      members: val[4])
                                }

                extension_decl: kEXTENSION module_name type_params tLPAREN tUIDENT tRPAREN class_members kEND
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Extension.new(module_name: val[1].value.absolute!,
                                                                         name: val[4].value,
                                                                         location: loc,
                                                                         params: val[2],
                                                                         members: val[6])
                                }

                    alias_decl: kTYPE tIDENT type_params tEQ type
                                {
                                  loc = val[0].location + val[4].location
                                  name = AliasName.new(name: val[1].value)
                                  result = AST::Signature::Alias.new(location: loc,
                                                                     name: name,
                                                                     params: val[2],
                                                                     type: val[4])
                                }

                 self_type_opt: # nothing
                                {
                                  result = nil
                                }
                              | tCOLON type
                                {
                                  result = val[1]
                                }

                interface_name: tINTERFACE_NAME {
                                  name = InterfaceName.new(name: val[0].value)
                                  result = LocatedValue.new(location: val[0].value, value: name)
                                }

                   module_name: namespace {
            		              namespace = val[0].value
            		              component = namespace.path.last
            		              name = ModuleName.new(namespace: namespace.parent, name: component)
            		              result = LocatedValue.new(location: val[0].location, value: name)
              		              }

                     namespace: namespace0 {
                                  namespace = AST::Namespace.new(path: val[0].value, absolute: false)
                                  result = LocatedValue.new(location: val[0].location, value: namespace)
                                }
                              | tCOLON2 namespace0 {
                                  namespace = AST::Namespace.new(path: val[1].value, absolute: true)
                                  location = val[0].location + val[1].location
                                  result = LocatedValue.new(location: location, value: namespace)
                                }

                    namespace0: tUIDENT {
                                  result = LocatedValue.new(location: val[0].location, value: [val[0].value])
                                }
                              | tUIDENT tCOLON2 namespace0 {
                                  array = [val[0].value] + val[2].value
                                  location = val[0].location + val[2].location
                                  result = LocatedValue.new(location: location, value: array)
                                }

                  module_name0: tUIDENT
                                {
                                  result = LocatedValue.new(location: val[0].location, value: ModuleName.parse(val[0].value))
                                }
                              | tUIDENT tCOLON2 module_name0
                                {
                                  location = val[0].location + val.last.location
                                  name = ModuleName.parse(val[0].value) + val.last.value
                                  result = LocatedValue.new(location: location, value: name)
                                }

                 class_members: # nothing
                                {
                                  result = []
                                }
                              | class_member class_members
                                {
                                  result = [val[0]] + val[1]
                                }

                  class_member: instance_method_member
                              | module_method_member
                              | module_instance_method_member
                              | include_member
                              | extend_member
                              | ivar_member
                              | attr_reader_member
                              | attr_accessor_member

                   ivar_member: tIVAR_NAME tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Members::Ivar.new(
                                    location: loc,
                                    name: val[0].value,
                                    type: val[2]
                                  )
                                }

        instance_method_member: kDEF method_annotations method_name tCOLON method_type_union
                                {
                                  loc = val.first.location + val.last.last.location
                                  result = AST::Signature::Members::Method.new(
                                    name: val[2].value,
                                    types: val[4],
                                    kind: :instance,
                                    location: loc,
                                    attributes: val[1] || []
                                  )
                                }

          module_method_member: kDEF method_annotations kSELF tDOT method_name tCOLON method_type_union
                                {
                                  loc = val.first.location + val.last.last.location
                                  result = AST::Signature::Members::Method.new(
                                    name: val[4].value,
                                    types: val[6],
                                    kind: :module,
                                    location: loc,
                                    attributes: val[1] || []
                                  )
                                }

 module_instance_method_member: kDEF method_annotations kSELFQ tDOT method_name tCOLON method_type_union
                                {
                                  loc = val.first.location + val.last.last.location
                                  result = AST::Signature::Members::Method.new(
                                    name: val[4].value,
                                    types: val[6],
                                    kind: :module_instance,
                                    location: loc,
                                    attributes: val[1] || []
                                  )
                                }

                include_member: kINCLUDE module_name
                                {
                                  loc = val[0].location + val[1].location
                                  name = val[1].value
                                  result = AST::Signature::Members::Include.new(name: name, location: loc, args: [])
                                }
                              | kINCLUDE module_name tLT type_seq tGT
                                {
                                  loc = val[0].location + val[4].location
                                  name = val[1].value
                                  result = AST::Signature::Members::Include.new(name: name, location: loc, args: val[3])
                                }

                 extend_member: kEXTEND module_name
                                {
                                  loc = val[0].location + val[1].location
                                  name = val[1].value
                                  result = AST::Signature::Members::Extend.new(name: name, location: loc, args: [])
                                }
                              | kEXTEND module_name tLT type_seq tGT
                                {
                                  loc = val[0].location + val[4].location
                                  name = val[1].value
                                  result = AST::Signature::Members::Extend.new(name: name, location: loc, args: val[3])
                                }

            attr_reader_member: kATTR_READER method_name attr_ivar_opt tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Members::Attr.new(location: loc, name: val[1].value, kind: :reader, ivar: val[2], type: val[4])
                                }

          attr_accessor_member: kATTR_ACCESSOR method_name attr_ivar_opt tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Signature::Members::Attr.new(location: loc, name: val[1].value, kind: :accessor, ivar: val[2], type: val[4])
                                }

                 attr_ivar_opt: # nothing
                                {
                                  result = nil
                                }
                              | tLPAREN tRPAREN
                                {
                                  result = false
                                }
                              | tLPAREN tIVAR_NAME tRPAREN
                                {
                                  result = val[1].value
                                }

            method_annotations: # nothing
                                {
                                  result = nil
                                }
                              | tLPAREN method_annotation_seq tRPAREN
                                {
                                  result = val[1]
                                }

         method_annotation_seq: method_annotation_keyword
                                {
                                  result = [val[0]]
                                }
                              | method_annotation_keyword tCOMMA method_annotation_seq
                                {
                                  result = [val[0]] + val[2]
                                }

     method_annotation_keyword: kCONSTRUCTOR
                                {
                                  result = val[0].value
                                }
                              | kINCOMPATIBLE
                                {
                                  result = val[0].value
                                }

                     super_opt: # nothing
                                {
                                  result = nil
                                }
                              | tLTCOLON super_class
                                {
                                  result = val[1]
                                }

                   super_class: module_name
                                {
                                  result = AST::Signature::SuperClass.new(location: val[0].location, name: val[0].value, args: [])
                                }
                              | module_name tLT type_seq tGT
                                {
                                  loc = val[0].location + val[3].location
                                  name = val[0].value
                                  result = AST::Signature::SuperClass.new(location: loc, name: name, args: val[2])
                                }

                   type_params: # nothing
                                {
                                  result = nil
                                }
                              | tLT type_param_seq tGT
                                {
                                  location = val[0].location + val[2].location
                                  result = AST::TypeParams.new(location: location, variables: val[1])
                                }

                type_param_seq: tVAR
                                {
                                  result = [val[0].value]
                                }
                              | tVAR tCOMMA type_param_seq
                                {
                                  result = [val[0].value] + val[2]
                                }

             interface_members: # nothing
                                {
                                  result = []
                                }
                              | interface_method interface_members
                                {
                                  result = val[1].unshift(val[0])
                                }

              interface_method: kDEF method_name tCOLON method_type_union
                                {
                                  loc = val[0].location + val[3].last.location
                                  result = AST::Signature::Interface::Method.new(location: loc, name: val[1].value, types: val[3])
                                }

             method_type_union: method_type
                                {
                                  result = [val[0]]
                                }
                              | method_type tBAR method_type_union
                                {
                                  result = [val[0]] + val[2]
                                }

                   method_name: method_name0
                              | tSTAR
                              | tSTAR2
                              | tPERCENT
                              | tMINUS
                              | tLT
                              | tGT
                              | tUMINUS
                              | tBAR
                                {
                                  result = LocatedValue.new(location: val[0].location, value: :|)
                                }
                              | method_name0 tEQ
                                {
                                  raise ParseError, "\nunexpected method name #{val[0].to_s} =" unless val[0].location.pred?(val[1].location)
                                  result = LocatedValue.new(location: val[0].location + val[1].location,
                                                           value: :"#{val[0].value}=")
                                }
                              | method_name0 tQUESTION
                                {
                                  raise ParseError, "\nunexpected method name #{val[0].to_s} ?" unless val[0].location.pred?(val[1].location)
                                  result = LocatedValue.new(location: val[0].location + val[1].location,
                                                           value: :"#{val[0].value}?")
                                }
                              | method_name0 tBANG
                                {
                                  raise ParseError, "\nunexpected method name #{val[0].to_s} !" unless val[0].location.pred?(val[1].location)
                                  result = LocatedValue.new(location: val[0].location + val[1].location,
                                                           value: :"#{val[0].value}!")
                                }
                              | tGT tGT
                                {
                                  raise ParseError, "\nunexpected method name > >" unless val[0].location.pred?(val[1].location)
                                  result = LocatedValue.new(location: val[0].location + val[1].location, value: :>>)
                                }
                              | kNIL tQUESTION
                                {
                                  raise ParseError, "\nunexpected method name #{val[0].to_s} ?" unless val[0].location.pred?(val[1].location)
                                  result = LocatedValue.new(location: val[0].location + val[1].location,
                                                         value: :"nil?")
                                }

                  method_name0: tIDENT
                              | tUIDENT
                              | tINTERFACE_NAME
                              | kANY
                              | kVOID
                              | kINTERFACE
                              | kEND
                              | tPLUS
                              | kCLASS
                              | kMODULE
                              | kINSTANCE
                              | kEXTEND
                              | kINCLUDE
                              | tOPERATOR
                              | tHAT
                              | tBANG
                              | kBLOCK
                              | kBREAK
                              | kMETHOD
                              | kBOOL
                              | kTYPE
                              | kCONSTRUCTOR
                                {
                                  result = LocatedValue.new(location: val[0].location, value: :constructor)
                                }
                              | kNOCONSTRUCTOR
                                {
                                  result = LocatedValue.new(location: val[0].location, value: :noconstructor)
                                }
                              | kATTR_READER
                              | kATTR_ACCESSOR
                              | kINCOMPATIBLE

                    annotation: kAT_TYPE kVAR subject tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::VarType.new(location: loc,
                                                                        name: val[2].value,
                                                                        type: val[4])
                                }
                              | kAT_TYPE kMETHOD subject tCOLON method_type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::MethodType.new(location: loc,
                                                                           name: val[2].value,
                                                                           type: val[4])
                                }
                              | kAT_TYPE kRETURN tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::ReturnType.new(type: val[3], location: loc)
                                }
                              | kAT_TYPE kBLOCK tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::BlockType.new(type: val[3], location: loc)
                                }
                              | kAT_TYPE kSELF tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::SelfType.new(type: val[3], location: loc)
                                }
                              | kAT_TYPE kCONST module_name tCOLON type
                                {
                                  loc = val[0].location + val[4].location
                                  result = AST::Annotation::ConstType.new(name: val[2].value,
                                                                          type: val[4],
                                                                          location: loc)
                                }
                              | kAT_TYPE kINSTANCE tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::InstanceType.new(type: val[3], location: loc)
                                }
                              | kAT_TYPE kMODULE tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::ModuleType.new(type: val[3], location: loc)
                                }
                              | kAT_TYPE kIVAR tIVAR_NAME tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::IvarType.new(name: val[2].value, type: val[4], location: loc)
                                }
                              | kAT_IMPLEMENTS module_name type_params
                                {
                                  loc = val[0].location + (val[2]&.location || val[1].location)
                                  args = val[2]&.variables || []
                                  name = AST::Annotation::Implements::Module.new(name: val[1].value, args: args)
                                  result = AST::Annotation::Implements.new(name: name, location: loc)
                                }
                              | kAT_DYNAMIC dynamic_names
                                {
                                  loc = val[0].location + val[1].last.location
                                  result = AST::Annotation::Dynamic.new(names: val[1], location: loc)
                                }
                              | kAT_TYPE kBREAK tCOLON type
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::BreakType.new(type: val[3], location: loc)
                                }

                 dynamic_names: dynamic_name tCOMMA dynamic_names
                                {
                                  result = [val[0]] + val[2]
                                }
                              | dynamic_name
                                {
                                  result = val
                                }

                  dynamic_name: method_name
                                {
                                  result = AST::Annotation::Dynamic::Name.new(name: val[0].value, location: val[0].location, kind: :instance)
                                }
                              | kSELF tDOT method_name
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::Dynamic::Name.new(name: val[2].value, location: loc, kind: :module)
                                }
                              | kSELFQ tDOT method_name
                                {
                                  loc = val.first.location + val.last.location
                                  result = AST::Annotation::Dynamic::Name.new(name: val[2].value, location: loc, kind: :module_instance)
                                }

                       subject: tIDENT
                                {
                                  result = val[0]
                                }
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
    new_token(:tARROW)
  when input.scan(/\?/)
    new_token(:tQUESTION)
  when input.scan(/!/)
    new_token(:tBANG, :!)
  when input.scan(/\(/)
    new_token(:tLPAREN, nil)
  when input.scan(/\)/)
    new_token(:tRPAREN, nil)
  when input.scan(/{/)
    new_token(:tLBRACE, nil)
  when input.scan(/}/)
    new_token(:tRBRACE, nil)
  when input.scan(/,/)
    new_token(:tCOMMA, nil)
  when input.scan(/:\w+/)
    new_token(:tSYMBOL, input.matched[1..-1].to_sym)
  when input.scan(/::/)
    new_token(:tCOLON2)
  when input.scan(/:/)
    new_token(:tCOLON)
  when input.scan(/\*\*/)
    new_token(:tSTAR2, :**)
  when input.scan(/\*/)
    new_token(:tSTAR, :*)
  when input.scan(/\+/)
    new_token(:tPLUS, :+)
  when input.scan(/\./)
    new_token(:tDOT)
  when input.scan(/<:/)
    new_token(:tLTCOLON)
  when input.scan(/\^/)
    new_token(:tHAT, :"^")
  when input.scan(/(\[\]=)|(\[\])|===|==|!=|<<|=~/)
    new_token(:tOPERATOR, input.matched.to_sym)
  when input.scan(/\[/)
    new_token(:tLBRACKET, nil)
  when input.scan(/\]/)
    new_token(:tRBRACKET, nil)
  when input.scan(/<=/)
    new_token(:tOPERATOR, :<=)
  when input.scan(/>=/)
    new_token(:tOPERATOR, :>=)
  when input.scan(/=/)
    new_token(:tEQ, :"=")
  when input.scan(/</)
    new_token(:tLT, :<)
  when input.scan(/>/)
    new_token(:tGT, :>)
  when input.scan(/nil\b/)
    new_token(:kNIL, :nil)
  when input.scan(/bool\b/)
    new_token(:kBOOL, :bool)
  when input.scan(/any\b/)
    new_token(:kANY, :any)
  when input.scan(/void\b/)
    new_token(:kVOID, :void)
  when input.scan(/type\b/)
    new_token(:kTYPE, :type)
  when input.scan(/interface\b/)
    new_token(:kINTERFACE, :interface)
  when input.scan(/incompatible\b/)
    new_token(:kINCOMPATIBLE, :incompatible)
  when input.scan(/end\b/)
    new_token(:kEND, :end)
  when input.scan(/\|/)
    new_token(:tBAR, :bar)
  when input.scan(/-@/)
    new_token(:tUMINUS, :"-@")
  when input.scan(/def\b/)
    new_token(:kDEF)
  when input.scan(/@type\b/)
    new_token(:kAT_TYPE)
  when input.scan(/@implements\b/)
    new_token(:kAT_IMPLEMENTS)
  when input.scan(/@dynamic\b/)
    new_token(:kAT_DYNAMIC)
  when input.scan(/const\b/)
    new_token(:kCONST, :const)
  when input.scan(/var\b/)
    new_token(:kVAR, :var)
  when input.scan(/return\b/)
    new_token(:kRETURN)
  when input.scan(/block\b/)
    new_token(:kBLOCK, :block)
  when input.scan(/break\b/)
    new_token(:kBREAK, :break)
  when input.scan(/method\b/)
    new_token(:kMETHOD, :method)
  when input.scan(/self\?/)
    new_token(:kSELFQ)
  when input.scan(/self\b/)
    new_token(:kSELF, :self)
  when input.scan(/'\w+/)
    new_token(:tVAR, input.matched.gsub(/\A'/, '').to_sym)
  when input.scan(/attr_reader\b/)
    new_token(:kATTR_READER, :attr_reader)
  when input.scan(/attr_accessor\b/)
    new_token(:kATTR_ACCESSOR, :attr_accessor)
  when input.scan(/instance\b/)
    new_token(:kINSTANCE, :instance)
  when input.scan(/class\b/)
    new_token(:kCLASS, :class)
  when input.scan(/module\b/)
    new_token(:kMODULE, :module)
  when input.scan(/include\b/)
    new_token(:kINCLUDE, :include)
  when input.scan(/extend\b/)
    new_token(:kEXTEND, :extend)
  when input.scan(/instance\b/)
    new_token(:kINSTANCE, :instance)
  when input.scan(/ivar\b/)
    new_token(:kIVAR, :ivar)
  when input.scan(/%/)
    new_token(:tPERCENT, :%)
  when input.scan(/-/)
    new_token(:tMINUS, :-)
  when input.scan(/&/)
    new_token(:tOPERATOR, :&)
  when input.scan(/~/)
    new_token(:tOPERATOR, :~)
  when input.scan(/\//)
    new_token(:tOPERATOR, :/)
  when input.scan(/extension\b/)
    new_token(:kEXTENSION, :extension)
  when input.scan(/constructor\b/)
    new_token(:kCONSTRUCTOR, :constructor)
  when input.scan(/noconstructor\b/)
    new_token(:kNOCONSTRUCTOR, :noconstructor)
  when input.scan(/\$\w+\b/)
    new_token(:tGVAR, input.matched.to_sym)
  when input.scan(/[A-Z]\w*/)
    new_token(:tUIDENT, input.matched.to_sym)
  when input.scan(/_\w+/)
    new_token(:tINTERFACE_NAME, input.matched.to_sym)
  when input.scan(/@\w+/)
    new_token(:tIVAR_NAME, input.matched.to_sym)
  when input.scan(/\d+/)
    new_token(:tINT, input.matched.to_i)
  when input.scan(/\"[^\"]*\"/)
    new_token(:tSTRING, input.matched[1...-1])
  when input.scan(/[a-z]\w*/)
    new_token(:tIDENT, input.matched.to_sym)
  end
end
