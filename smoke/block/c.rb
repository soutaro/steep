class OptionalBlock
  def optional_block
    yield
    30
  end
end

OptionalBlock.new.optional_block()
OptionalBlock.new.optional_block() { :foo }
