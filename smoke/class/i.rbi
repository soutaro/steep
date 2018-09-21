class IncompatibleSuper
  def foo: () -> Integer
  def initialize: (name: String) -> any
end

class IncompatibleChild < IncompatibleSuper
  def initialize: () -> any
  def (incompatible) foo: (Object) -> String
end
