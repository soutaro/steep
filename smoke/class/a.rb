class A
  # A#foo is defined and the implementation is compatible.
  def foo(x)
    x + ""
  end

  # A#bar is defined but the implementation is incompatible.
  # !expects MethodArityMismatch: method=bar
  def bar(y)
    y
  end

  # Object#to_s is defined but the implementation is incompatible.
  # !expects MethodBodyTypeMismatch: method=to_s, expected=::String, actual=::Integer
  def to_s
    3
  end

  # No method definition given via signature, there is no type error.
  def to_str
    5
  end

  # !expects MethodBodyTypeMismatch: method=self.baz, expected=::Integer, actual=::String
  def self.baz
    "baz"
  end
end
