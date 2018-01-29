class C
  # @implements C

  def foo
    self.class.new
  end

  def bar
    # !expects NoMethodError: type=C.class noconstructor, method=new
    self.class.new
  end
end
