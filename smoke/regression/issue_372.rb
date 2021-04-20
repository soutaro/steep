class Issue372
  def f(&block)
  end

  def g(&block)
    f(&block)
  end
end
