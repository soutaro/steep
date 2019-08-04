extension Object (X)
  def try: [A] { (instance) -> A } -> A
  def f: -> Object
end

extension Kernel (X)
  def new_module_method: () -> void
end

class Foo
  def f: -> String
end
