module Issue332
  module TimeDurationExtensions
    def -(other)
      if other.is_a?(Duration)
        Time.now
      else
        super(other)
      end
    end
  end
end
