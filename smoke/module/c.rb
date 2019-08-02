module A
  # @implements A

  def count
    if block_given?
      n = 0

      each do |_|
        n = n + 1
      end

      n
    else
      0
    end
  end

  # ok
  block_given?

  # !expects NoMethodError: type=(::Module & singleton(::A)), method=no_such_method_in_module
  no_such_method_in_module
end
