class IncompatibleChild
  def foo(arg)
    # @type var x: Symbol
    x = super()

    "123"
  end

  def initialize()
    super()

    super
  end
end
