class MethodReturnTypeAnnotationMismatch
  # @type method foo: () -> String
  def foo
    # @type return: Integer
    123
  end
end
