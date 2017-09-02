module A
  # @type instance: A
  # @type module: A.module

  def count
    # @type var n: Integer
    n = 0

    each do |_|
      n = n + 1
    end

    # @type var s: String
    # !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
    s = n

    n
  end
end
