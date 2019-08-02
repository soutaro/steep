class WithSingletonConstructor
  attr_reader foo: String

  def initialize: (foo: String) -> any
  def self.create: -> instance
end
