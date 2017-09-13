class Steep__Signature__Error
  def initialize: (signature: Steep__Signature) -> any
  def signature: -> Steep__Signature
end

class Steep__Signature__Errors__UnknownTypeName <: Steep__Signature__Error
  def initialize: (signature: Steep__Signature, type: Steep__Type) -> any
  def type: -> Steep__Type
end

class Steep__MethodType
  def substitute: (klass: Steep__Type, instance: Steep__Type, params: Hash<Symbol, Steep__Type>) -> Steep__MethodType
end

class Steep__Interface
  def initialize: (name: Symbol, methods: Hash<Symbol, Steep__Method>) -> any
end

class Steep__Method
  def initialize: (types: Array<Steep__MethodType>, super_method: Steep__Method) -> any
  def substitute: (klass: Steep__Type, instance: Steep__Type, params: Hash<Symbol, Steep__Type>) -> Steep__Method
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
