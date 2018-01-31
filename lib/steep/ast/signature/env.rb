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
            raise "Duplicated class: #{sig.name}" if classes.key?(sig.name.absolute!) || modules.key?(sig.name.absolute!)
            classes[sig.name.absolute!] = sig
          when Signature::Module
            raise "Duplicated module: #{sig.name}" if classes.key?(sig.name.absolute!) || modules.key?(sig.name.absolute!)
            modules[sig.name.absolute!] = sig
          when Signature::Interface
            raise "Duplicated interface: #{sig.name}" if interfaces.key?(sig.name)
            interfaces[sig.name] = sig
          when Signature::Extension
            extensions[sig.module_name.absolute!] ||= []
            if extensions[sig.module_name.absolute!].any? {|ext| ext.name == sig.name }
              raise "Duplicated extension: #{sig.module_name.absolute!} (#{sig.name})"
            end
            extensions[sig.module_name.absolute!] << sig
          else
            raise "Unknown signature:: #{sig}"
          end
        end

        def find_module(name, current_module: nil)
          find_name(modules, name, current_module: current_module) or raise "Unknown module: #{name}"
        end

        def find_class(name, current_module: nil)
          find_name(classes, name, current_module: current_module) or raise "Unknown class: #{name}"
        end

        def find_class_or_module(name, current_module: nil)
          sig =
            find_name(modules, name, current_module: current_module) ||
              find_name(classes, name, current_module: current_module)

          sig or raise "Unknown class/module: #{name}}"
        end

        def find_extensions(name, current_module: nil)
          find_name(extensions, name, current_module: current_module) || []
        end

        def find_name(hash, name, current_module:)
          if current_module
            hash[current_module + name] || find_name(hash, name, current_module: current_module.parent)
          else
            hash[name.absolute!]
          end
        end

        def find_interface(name)
          interfaces[name] or raise "Unknown interface: #{name}"
        end

        def module?(type_name, current_module: nil)
          name = type_name.map_module_name {|m| current_module ? current_module + m : m.absolute! }.name
          modules.key?(name)
        end

        def class?(type_name, current_module: nil)
          name = type_name.map_module_name {|m| current_module ? current_name + m : m.absolute! }.name
          classes.key?(name)
        end

        def each(&block)
          if block_given?
            classes.each_value(&block)
            modules.each_value(&block)
            interfaces.each_value(&block)
          else
            enum_for :each
          end
        end
      end
    end
  end
end
