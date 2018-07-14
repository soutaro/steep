class IncompatibleSuper
  def foo: () -> Integer
end

class IncompatibleChild <: IncompatibleSuper
  def (incompatible) foo: (Object) -> String
end
