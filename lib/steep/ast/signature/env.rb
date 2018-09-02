module Steep
  module AST
    module Signature
      class Env
        attr_reader :modules
        attr_reader :classes
        attr_reader :extensions
        attr_reader :interfaces
        attr_reader :constants
        attr_reader :globals
        attr_reader :aliases

        def initialize()
          @modules = {}
          @classes = {}
          @extensions = {}
          @interfaces = {}
          @constants = {}
          @globals = {}
          @aliases = {}
        end

        def assert_absolute_name(name)
          name.namespace.absolute? or raise "Absolute name expected: #{name}"
        end

        def add(sig)
          case sig
          when Signature::Class
            assert_absolute_name sig.name
            raise "Duplicated class: #{sig.name}" if classes.key?(sig.name) || modules.key?(sig.name)
            classes[sig.name] = sig
          when Signature::Module
            assert_absolute_name sig.name
            raise "Duplicated module: #{sig.name}" if classes.key?(sig.name) || modules.key?(sig.name)
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
          when Signature::Const
            assert_absolute_name sig.name
            constants[sig.name] = sig
          when Signature::Gvar
            raise "Duplicated global: #{sig.name}" if globals.key?(sig.name)
            globals[sig.name] = sig
          when Signature::Alias
            raise "Duplicated alias: #{sig.name}" if aliases.key?(sig.name)
            aliases[sig.name] = sig
          else
            raise "Unknown signature:: #{sig}"
          end
        end

        def find_module(name, current_module: AST::Namespace.root)
          find_name(modules, name, current_module: current_module) or raise "Unknown module: #{name}"
        end

        def find_class(name, current_module: AST::Namespace.root)
          find_name(classes, name, current_module: current_module) or raise "Unknown class: #{name}"
        end

        def find_class_or_module(name, current_module: AST::Namespace.root)
          sig =
            find_name(modules, name, current_module: current_module) ||
              find_name(classes, name, current_module: current_module)

          sig or raise "Unknown class/module: #{name}}"
        end

        def find_extensions(name, current_module: AST::Namespace.root)
          find_name(extensions, name, current_module: current_module) || []
        end

        def find_const(name, current_module: Namespace.root)
          find_name(constants, name, current_module: current_module)
        end

        def find_gvar(name)
          globals[name]
        end

        def find_alias(name)
          aliases[name]
        end

        def find_name(hash, name, current_module:)
          current_module.absolute? or raise "Current namespace should be absolute: #{current_module}"

          if (object = hash[name.in_namespace(current_module)])
            object
          else
            unless current_module.empty?
              find_name(hash, name, current_module: current_module.parent)
            end
          end
        end

        def find_interface(name)
          interfaces[name] or raise "Unknown interface: #{name}"
        end

        def class_name?(name)
          assert_absolute_name name
          classes.key?(name)
        end

        def module_name?(name)
          assert_absolute_name name
          modules.key?(name)
        end

        def const_name?(name)
          assert_absolute_name name
          constants.key?(name)
        end

        def each(&block)
          if block_given?
            classes.each_value(&block)
            modules.each_value(&block)
            interfaces.each_value(&block)
            constants.each_value(&block)
          else
            enum_for :each
          end
        end
      end
    end
  end
end
