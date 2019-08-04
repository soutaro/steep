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
      end

      def run
        source_paths.each do |path|
          each_file_in_path(".rb", path) do |file_path|
            buffer = ::Parser::Source::Buffer.new(file_path.to_s, 1)
            buffer.source = file_path.read
            node = Source.parser.parse(buffer)
            Generator.new(node: node, stderr: stderr).write(io: stdout)
          end
        end
        0
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

          attr_accessor :has_subclass

          def namespace_class?
            has_subclass && methods.empty? && singleton_methods.empty?
          end
        end

        attr_reader :node
        attr_reader :modules
        attr_reader :constants
        attr_reader :stderr

        def initialize(node:, stderr:)
          @node = node
          @stderr = stderr
          @modules = []
          @constants = {}
        end

        def write(io:)
          generate(node, current_path: [])

          modules.each do |mod|
            unless mod.namespace_class?
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

          constants.each do |name, ty|
            io.puts "#{name}: #{ty}"
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

            if current_module
              current_module.has_subclass = true
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

            if current_module
              current_module.has_subclass = true
            end

          when :def
            name, args, body = node.children

            if current_module
              current_module.methods[name] = "(#{arg_types(args)}) -> #{guess_type(body)}"
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
              current_module.ivars[name] = guess_type(node.children[1])
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
                current_module.singleton_methods[name] = "(#{arg_types(args)}) -> #{guess_type(body)}"
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

            constants[full_name(current_path, node.children[1])] = guess_type(node.children[2])

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

        def guess_type(node)
          return "any" unless node
          case node.type
          when :false, :true
            "bool"
          when :int
            "Integer"
          when :float
            "Float"
          when :complex
            "Complex"
          when :rational
            "Rational"
          when :str, :dstr, :xstr
            "String"
          when :sym, :dsym
            "Symbol"
          when :regexp
            "Regexp"
          when :array
            "Array[any]"
          when :hash
            "Hash[any, any]"
          when :irange, :erange
            "Range[any]"
          when :lvasgn, :ivasgn, :cvasgn, :gvasgn, :casgn
            guess_type(node.children.last)
          when :send
            if node.children[1] == :[]=
              guess_type(node.children.last)
            else
              "any"
            end
          when :begin
            # should support shortcut return?
            guess_type(node.children.last)
          when :return
            children = node.children
            if children.size == 1
              guess_type(node.children.last)
            else
              "Array[any]" # or Tuple or any?
            end
          when :if
            children = node.children
            if children[2]
              ty1 = guess_type(children[1])
              ty2 = guess_type(children[2])
              if ty1 == ty2
                ty1
              else
                "any"
              end
            else
              "void" # assuming no-else if statement implies void
            end
          when :while, :until, :while_post, :until_post, :for
            "void"
          when :case
            children = node.children
            if children.last
              ty = guess_type(children.last)
              children[1..-2].each do |child|
                return "any" if ty != guess_type(child.children.last)
              end
              ty
            else
              "any"
            end
          when :masgn
            "void" # assuming masgn implies void
          else
            "any"
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
              "?#{guess_type(arg.children[1])}"
            when :restarg
              "*any"
            when :kwarg
              "#{arg.children.first}: any"
            when :kwoptarg
              "?#{arg.children.first}: #{guess_type(arg.children[1])}"
            when :kwrestarg
              "**any"
            end
          end.compact.join(", ")
        end
      end
    end
  end
end
