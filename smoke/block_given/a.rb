class BlockGivenTest
  # Anonymous block with block_given? guard (the exact scenario from issue #1099)
  def each_anonymous(&)
    return enum_for(:each_anonymous) unless block_given?

    [1, 2, 3].each(&)
  end

  # Named block with block_given? guard
  def each_named(&blk)
    return enum_for(:each_named) unless block_given?

    [1, 2, 3].each(&blk)
  end

  # Required block (non-optional) — should not error
  def required_block(&)
    [1, 2, 3].each(&)
  end

  # block_given? with if (truthy branch)
  def each_if(&)
    if block_given?
      [1, 2, 3].each(&)
    else
      enum_for(:each_if)
    end
  end
end
