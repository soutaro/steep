module A
  # @implements A

  def count
    # @type var n: ::Integer
    n = 0

    each do |_|
      n = n + 1
    end

    # @type var s: String
    s = n

    foo()

    n
  end
end
