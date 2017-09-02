# !expects@+2 MethodDefinitionMissing: module=A, method=baz
# !expects MethodDefinitionMissing: module=A, method=self.bar
class A
  # @implements A

  def foo()
  end

  def bar()
  end

  def self.baz
  end
end
