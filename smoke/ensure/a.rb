# @type var a: Integer
# @type var b: Integer

a = begin
      'foo'
    ensure
      b = :foo
      1
    end

# @type method foo: (String) -> String

def foo(a)
  10
ensure
  1 + '1'
  a
end
