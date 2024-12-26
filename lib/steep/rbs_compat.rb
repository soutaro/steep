unless ::RBS::TypeName.singleton_class.method_defined?(:parse)
  # Before RBS 3.8.0
  class ::RBS::TypeName
    def self.parse(string)
      TypeName(string)
    end
  end
end
