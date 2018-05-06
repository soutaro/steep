module Steep
  module Drivers
    class Scaffold
      attr_reader :source_paths
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :labeling

      include Utils::EachSignature

      def initialize(source_paths:, stdout:, stderr:)
        @source_paths = source_paths
        @stdout = stdout
        @stderr = stderr

        @labeling = ASTUtils::Labeling.new
      end

      def run
        each_ruby_source(source_paths, false) do |source|
          Generator.new(source: source, stderr: stderr).write(io: stdout)
        end
      end

      class Generator
        class Module
          attr_reader :name
          attr_reader :methods
          attr_reader :singleton_methods
          attr_reader :ivars
          attr_reader :kind

          def initialize(name:, kind:)
            @kind = kind
            @name = name
            @ivars = {}
            @methods = {}
            @singleton_methods = {}
          end

          def class?
            kind == :class
          end

          def module?
            kind == :module
          end
        end

        attr_reader :source
        attr_reader :modules
        attr_reader :constants
        attr_reader :stderr

        def initialize(source:, stderr:)
          @source = source
          @stderr = stderr
          @modules = []
          @constants = []
        end

        def write(io:)
          generate(source.node, current_path: [])

          modules.each do |mod|
            unless mod.methods.empty? && mod.singleton_methods.empty?
              io.puts "#{mod.kind} #{mod.name}"

              mod.ivars.each do |name, type|
                io.puts "  #{name}: #{type}"
              end

              mod.methods.each do |name, type|
                io.puts "  def #{name}: #{type}"
              end

              mod.singleton_methods.each do |name, type|
                io.puts "  def self.#{name}: #{type}"
              end

              io.puts "end"
              io.puts
            end
          end

          constants.each do |name|
            io.puts "#{name}: any"
          end
        end

        def module_name(name)
          if name.type == :const
            prefix = name.children[0]
            if prefix
              "#{module_name(prefix)}::#{name.children[1]}"
            else
              name.children[1].to_s
            end
          else
            stderr.puts "Unexpected node for class name: #{name}"
            return "____"
          end
        end

        def full_name(current_path, name)
          (current_path + [name]).join("::")
        end

        def generate(node, current_path:, current_module: nil, is_instance_method: false)
          case node.type
          when :module
            name = module_name(node.children[0])
            mod = Module.new(name: full_name(current_path, name), kind: :module)
            modules << mod

            if node.children[1]
              generate(node.children[1],
                       current_path: current_path + [name],
                       current_module: mod)
            end

          when :class
            name = module_name(node.children[0])
            klass = Module.new(name: full_name(current_path, name), kind: :class)
            modules << klass

            if node.children[2]
              generate(node.children[2],
                       current_path: current_path + [name],
                       current_module: klass)
            end

          when :def
            name, args, body = node.children

            if current_module
              current_module.methods[name] = "(#{arg_types(args)}) -> any"
            end

            if body
              generate(body,
                       current_path: current_path,
                       current_module: current_module,
                       is_instance_method: true)
            end

          when :ivar, :ivasgn
            name = node.children[0]

            if current_module && is_instance_method
              current_module.ivars[name] = "any"
            end

            each_child_node(node) do |child|
              generate(child,
                       current_path: current_path,
                       current_module: current_module,
                       is_instance_method: is_instance_method)
            end

          when :defs
            if node.children[0].type == :self
              _, name, args, body = node.children

              if current_module
                current_module.singleton_methods[name] = "(#{arg_types(args)}) -> any"
              end

              if body
                generate(body,
                         current_path: current_path,
                         current_module: current_module,
                         is_instance_method: false)
              end
            end

          when :casgn
            if node.children[0]
              stderr.puts "Unexpected casgn: #{node}, #{node.loc.line}"
            end

            constants << full_name(current_path, node.children[1])

            if node.children[2]
              generate(node.children[2],
                       current_path: current_path,
                       current_module: current_module,
                       is_instance_method: is_instance_method)
            end

          else
            each_child_node(node) do |child|
              generate(child, current_path: current_path, current_module: current_module, is_instance_method: is_instance_method)
            end
          end
        end

        def each_child_node(node, &block)
          node.children.each do |child|
            if child.is_a?(::AST::Node)
              yield child
            end
          end
        end

        def arg_types(args)
          args.children.map do |arg|
            case arg.type
            when :arg
              "any"
            when :optarg
              "?any"
            when :restarg
              "*any"
            when :kwarg
              "#{arg.children.first.name}: any"
            when :kwoptarg
              "?#{arg.children.first.name}: any"
            when :kwrestarg
              "**any"
            end
          end.compact.join(", ")
        end
      end
    end
  end
end
