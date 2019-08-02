module A
  # @implements A

  def count
    # @type var n: ::Integer
    n = 0

    each do |_|
      n = n + 1
    end

    # @type var s: String
    # !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
    s = n

    # !expects NoMethodError: type=(::A & ::Object & ::_Each[::Integer, ::A]), method=foo
    foo()

    n
  end
end
