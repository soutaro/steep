class Steep__Signature__Error
  def initialize: (signature: Steep__Signature) -> any
  def signature: -> Steep__Signature
  def puts: (any) -> any
end

class Steep__Signature__Errors__UnknownTypeName <: Steep__Signature__Error
  def initialize: (signature: Steep__Signature, type: Steep__Type) -> any
  def type: -> Steep__Type
end

class Steep__BlockType
  def params: -> Steep__MethodParams
  def return_type: -> Steep__Type
end

class Steep__MethodParams
  def each_type: { (Steep__Type) -> any } -> instance
end

class Steep__MethodType
  def substitute: (klass: Steep__Type, instance: Steep__Type, params: Hash<Symbol, Steep__Type>) -> Steep__MethodType
  def updated: (?type_params: Array<Symbol>, ?params: Steep__MethodParams, ?block: any, ?return_type: Steep__Type) -> Steep__MethodType
  def params: -> Steep__MethodParams
  def return_type: -> Steep__Type
  def block: -> Steep__BlockType
end

class Steep__Interface
  def initialize: (name: Symbol, methods: Hash<Symbol, Steep__Method>) -> any
end

class Steep__Method
  def initialize: (types: Array<Steep__MethodType>, super_method: Steep__Method) -> any
  def substitute: (klass: Steep__Type, instance: Steep__Type, params: Hash<Symbol, Steep__Type>) -> Steep__Method
  def types: -> Array<Steep__MethodType>
end

class Steep__Signature
end

class Steep__Signature__Member
end

class Steep__Signature__Errors__IncompatibleOverride <: Steep__Signature__Error
  def initialize: (signature: Steep__Signature, method_name: Symbol, this_method: Steep__Method, super_method: Steep__Method) -> any
  def method_name: -> Symbol
  def this_method: -> Steep__Method
  def super_method: -> Steep__Method
end

class Steep__SignatureMember__Method <: Steep__Signature__Member
  def initialize: (name: Symbol, types: Array<Steep__MethodType>) -> any
  def name: -> Symbol
  def types: -> Array<Steep__MethodType>
end

class Steep__SignatureMember__Include <: Steep__Signature__Member
  def initialize: (name: Symbol) -> any
  def name: -> Symbol
end

class Steep__SignatureMember__Extend <: Steep__Signature__Member
  def initialize: (name: Symbol) -> any
  def name: -> Symbol
end

interface _Steep__SignatureMember__Mixin
  def name: -> Steep__Type
end

interface _Steep__WithMethods
  def instance_methods: (assignability: any, klass: Steep__Type, instance: Steep__Type, params: Array<Steep__Type>) -> Hash<Symbol, Steep__Method>
  def module_methods: (assignability: any, klass: Steep__Type, instance: Steep__Type, params: Array<Steep__Type>) -> Hash<Symbol, Steep__Method>
  def type_application_hash: (Array<Steep__Type>) -> Hash<Symbol, Steep__Type>
  def members: -> Array<Steep__Signature__Member>
  def is_class?: -> _Boolean
end

module Steep__Signature__WithMethods : _Steep__WithMethods
  def instance_methods: (assignability: any, klass: Steep__Type, instance: Steep__Type, params: Array<Steep__Type>) -> Hash<Symbol, Steep__Method>
  def module_methods: (assignability: any, klass: Steep__Type, instance: Steep__Type, params: Array<Steep__Type>) -> Hash<Symbol, Steep__Method>
  def merge_methods: (Hash<Symbol, Steep__Method>, Hash<Symbol, Steep__Method>) -> Hash<Symbol, Steep__Method>
end

interface _Steep__WithMembers
  def members: -> Array<Steep__Signature__Member>
  def params: -> Array<Symbol>
end

module Steep__Signature__WithMembers : _Steep__WithMembers
  def each_type: { (Steep__Type) -> any } -> any
  def validate_mixins: (any, Steep__Interface) -> any
end

interface _Steep__WithParams
end

module Steep__Signature__WithParams : _Steep__WithParams
  def type_application_hash: (Array<Steep__Type>) -> Hash<Symbol, Steep__Type>
end

class Steep__Signature__Module
  include Steep__Signature__WithMethods
  include Steep__Signature__WithMembers
  include Steep__Signature__WithParams

  def initialize: (name: Symbol, params: Array<Symbol>, members: Array<Steep__Signature__Member>, self_type: Steep__Type) -> any
  def name: -> Symbol
  def params: -> Array<Symbol>
  def members: -> Array<Steep__Signature__Member>
  def self_type: -> Steep__Type
  def is_class?: -> _Boolean
end

class Steep__Signature__Class
  include Steep__Signature__WithMethods
  include Steep__Signature__WithMembers
  include Steep__Signature__WithParams

  def initialize: (name: Symbol, params: Array<Symbol>, members: Array<Steep__Signature__Member>, super_class: Steep__Types__Name) -> any
  def name: -> Symbol
  def params: -> Array<Symbol>
  def members: -> Array<Steep__Signature__Member>
  def super_class: -> Steep__Types__Name
  def is_class?: -> _Boolean
end

class Steep__Signature__Extension
  def initialize: (module_name: Symbol, extension_name: Symbol, members: Array<Steep__Signature__Member>) -> any
  def module_name: -> Symbol
  def extension_name: -> Symbol
  def members: -> Array<Steep__Signature__Member>
  def name: -> Symbol
end

class Steep__Signature__Interface
  def initialize: (name: Symbol, params: Array<Symbol>, methods: Hash<Symbol, Array<Steep__MethodType>>) -> any

  def name: -> Symbol
  def params: -> Array<Symbol>
  def methods: -> Hash<Symbol, Array<Steep__MethodType>>

  def to_interface: (klass: Steep__Type, instance: Steep__Type, params: Array<Steep__Type>) -> any
  def validate: (any) -> any
end
