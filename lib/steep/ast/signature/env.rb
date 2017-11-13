module Steep
  module AST
    module Signature
      class Env
        attr_reader :modules
        attr_reader :classes
        attr_reader :extensions
        attr_reader :interfaces

        def initialize()
          @modules = {}
          @classes = {}
          @extensions = {}
          @interfaces = {}
        end

        def add(sig)
          case sig
          when Signature::Class
            raise "Duplicated class: #{sig.name}" if classes.key?(sig.name) || modules.key?(sig.name)
            classes[sig.name] = sig
          when Signature::Module
            raise "Duplicated module: #{sig.name}" if classes.key?(sig.name) || modules.key?(sig.name)
            modules[sig.name] = sig
          when Signature::Interface
            raise "Duplicated interface: #{sig.name}" if interfaces.key?(sig.name)
            interfaces[sig.name] = sig
          when Signature::Extension
            key = [sig.module_name, sig.name]
            raise "Duplicated extension: #{sig.module_name} (#{sig.name})" if extensions.key?(key)
            extensions[key] = sig
          else
            raise "Unknown signature:: #{sig}"
          end
        end

        def find_module(name)
          modules[name] or raise "Unknown module: #{name}"
        end

        def find_class(name)
          classes[name] or raise "Unknown class: #{name}"
        end

        def find_class_or_module(name)
          modules[name] || classes[name] or raise "Unknown class/module: #{name}"
        end

        def find_extension(name, extension)
          extensions[[name, extension]] or raise "Unknown extension: #{name} (#{extension})"
        end

        def find_interface(name)
          interfaces[name] or raise "Unknown interface: #{name}"
        end

        def module?(name)
          modules.key?(name)
        end

        def class?(name)
          classes.key?(name)
        end
      end
    end
  end
end
