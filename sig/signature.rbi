class Steep__Signature__Error
  def initialize: (signature: Steep__Signature) -> any
  def signature: -> Steep__Signature
end

class Steep__Signature__Errors__UnknownTypeName <: Steep__Signature__Error
  def initialize: (signature: Steep__Signature, type: Steep__Type) -> any
  def type: -> Steep__Type
end

class Steep__Interface__Method
end

class Steep__Signature
end

class Steep__Signature__Errors__IncompatibleOverride <: Steep__Signature__Error
  def initialize: (signature: Steep__Signature, method_name: Symbol, this_method: Steep__Interface__Method, super_method: Steep__Interface__Method) -> any
  def method_name: -> Symbol
  def this_method: -> Steep__Interface__Method
  def super_method: -> Steep__Interface__Method
end
