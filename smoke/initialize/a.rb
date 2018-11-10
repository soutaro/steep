class A
  # @implements A

  def initialize()
    
  end

  def foo()
    # initialize is a private method, so can be called here
    initialize()
  end
end
