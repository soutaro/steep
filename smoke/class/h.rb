class WithSingletonConstructor
  # @dynamic foo
  attr_reader :foo

  def initialize(foo:)
    @foo = foo
  end

  def self.create()
    new(foo: "hoge")
  end

  new(foo: "hoge")
  create()
end
