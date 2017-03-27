module Steep
  class TypeAssignability
    attr_reader :interfaces

    def initialize()
      @interfaces = {}
    end

    def add_interface(interface)
      interfaces[interface.name] = interface
    end

    def test(src:, dest:, known_pairs: [])
      if src.is_a?(Types::Any) || dest.is_a?(Types::Any)
        true
      else
        test_interface(to_interface(src.name), to_interface(dest.name), known_pairs)
      end
    end

    def test_interface(src, dest, known_pairs)
      if src.name == dest.name
        return true
      end

      src.methods.all? do |name, src_method|
        if dest.methods.key?(name)
          dest_method = dest.methods[name]
          test_method(src_method, dest_method, known_pairs)
        end
      end
    end

    def test_method(src, dest, known_pairs)
      true
    end

    def to_interface(name)
      interfaces[name]
    end
  end
end
