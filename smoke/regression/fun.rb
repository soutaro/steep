class Fun
  def foo(v)
    !v.nil? && foo2(v)
  end

  def foo2(_)
  end
end
