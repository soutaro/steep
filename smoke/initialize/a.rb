class A
  # @implements A

  def initialize()
    
  end

  def foo()
    # !expects NoMethodError: type=A, method=initialize
    initialize()
  end
end
