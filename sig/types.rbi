class Steep__TypeName
  def initialize: (name: Symbol) -> any
end

class Steep__Type
  def closed?: -> _Boolean
  def substitute: (klass: Steep__Type, instance: Steep__Type, params: Hash<Symbol, Steep__Type>) -> instance
end

class Steep__Types__Name <: Steep__Type
  def initialize: (name: Steep__TypeName, params: Array<Steep__Type>) -> any

  def name: -> Steep__TypeName
  def params: -> Array<Steep__Type>

  def self.interface: (name: Symbol, ?params: Array<Steep__Type>) -> Steep__Types__Name
  def self.module: (name: Symbol, ?params: Array<Steep__Type>) -> Steep__Types__Name
  def self.instance: (name: Symbol, ?params: Array<Steep__Type>) -> Steep__Types__Name
end

class Steep__Types__Union <: Steep__Type
  def initialize: (types: Array<Steep__Type>) -> any
  def types: -> Array<Steep__Type>
end

class Steep__Types__Merge <: Steep__Type
  def initialize: (types: Array<Steep__Type>) -> any
  def types: -> Array<Steep__Type>
end

class Steep__Types__Var <: Steep__Type
  def initialize: (name: Symbol) -> any
  def name: -> Symbol
end

class Steep__Types__Instance <: Steep__Type
end

class Steep__Types__Class <: Steep__Type
end

class Steep__Types__Any <: Steep__Type
end
