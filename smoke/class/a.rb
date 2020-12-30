class A
  # A#foo is defined and the implementation is compatible.
  def foo(x)
    x + ""
  end

  # A#bar is defined but the implementation is incompatible.
  def bar(y)
    y
  end

  # Object#to_s is defined but the implementation is incompatible.
  def to_s
    3
  end

  # No method definition given via signature, there is no type error.
  def to_str
    5
  end

  def self.baz
    "baz"
  end
end
