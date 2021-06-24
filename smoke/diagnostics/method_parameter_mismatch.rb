class MethodParameterMismatch
  # @type method foo: (?String, *Integer) -> void
  def foo(a, b)
  end

  # @type method bar: (?name: String) -> void
  def self.bar(name:)

  end
end
