class EmptyYield
  def foo
    yield ""

    # ↓ Expect error without yield
    yield
  end
end
