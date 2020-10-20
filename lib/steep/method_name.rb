module Steep
  InstanceMethodName = Struct.new(:type_name, :method_name, keyword_init: true) do
    def to_s
      "#{type_name}##{method_name}"
    end
  end

  SingletonMethodName = Struct.new(:type_name, :method_name, keyword_init: true) do
    def to_s
      "#{type_name}.#{method_name}"
    end
  end

  module ::Kernel
    def MethodName(string)
      case string
      when /#/
        type_name, method_name = string.split(/#/, 2)
        InstanceMethodName.new(type_name: TypeName(type_name), method_name: method_name.to_sym)
      when /\./
        type_name, method_name = string.split(/\./, 2)
        SingletonMethodName.new(type_name: TypeName(type_name), method_name: method_name.to_sym)
      else
        raise "Unexpected method name: #{string}"
      end
    end
  end
end
