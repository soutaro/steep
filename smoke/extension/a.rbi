extension Object (X)
  def try: <'a> { (instance) -> 'a } -> 'a
  def f: -> Object
end

extension Kernel (X)
  def self.new_module_method: () -> void
end

class Foo
  def f: -> String
end
