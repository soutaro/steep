# @type var a: Integer

a = begin
      'foo'
    rescue
      1
    end

# @type var b: Integer

b = 'foo' rescue 1

# @type var c: Integer

c = begin
      'foo'
    rescue RuntimeError
      :sym
    rescue StandardError
      1
    end

# @type var e: Integer

e = begin
      'foo'
    rescue RuntimeError
      :sym
    rescue StandardError
      1
    else
      [1]
    end

# @type method foo: (String) -> String

def foo(a)
  10
rescue
  'foo'
end

# when empty
begin
rescue
else
ensure
end
