class WithSingletonConstructor
  # @dynamic foo
  attr_reader :foo

  def initialize(foo:)
    @foo = foo
  end

  def self.create()
    instance = new(foo: "hoge")

    instance.foo

    _ = instance
  end

  new(foo: "hoge")
  create().foo
end
