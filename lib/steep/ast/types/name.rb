module Steep
  module AST
    module Types
      module Name
        class Base
          attr_reader :name

          def initialize(name:)
            @name = name
          end

          include Helper::NoFreeVariables

          def subst(s)
            self
          end

          def level
            [0]
          end

          def map_type(&block)
            self
          end
        end

        class Applying < Base
          attr_reader :args

          def initialize(name:, args:)
            super(name: name)
            @args = args
          end

          # Returns a shared instance for the given name and args
          #
          # Types without free variables are cached and shared, which makes the identity test
          # the fast path of `#==`/`#eql?` work more frequently.
          # Note that the sharing is best-effort -- types constructed with `.new` are still
          # equal to the shared instances by the structural comparison.
          #
          def self.intern(name:, args:)
            if args.empty?
              no_args_table = (@no_args_table ||= {}) #: Hash[RBS::TypeName, instance]
              no_args_table[name] ||= new(name: name, args: args)
            else
              table = (@with_args_table ||= {}) #: Hash[[RBS::TypeName, Array[AST::Types::t]], instance]
              key = [name, args] #: [RBS::TypeName, Array[AST::Types::t]]
              if type = table[key]
                type
              else
                type = new(name: name, args: args)
                if args.all? {|arg| arg.free_variables.empty? }
                  table[key] = type
                end
                type
              end
            end
          end

          def ==(other)
            return true if equal?(other)

            other.class == self.class &&
              other.name == name &&
              other.args == args
          end

          alias eql? ==

          def hash
            @hash ||= self.class.hash ^ name.hash ^ args.hash
          end

          def to_s
            if args.empty?
              "#{name}"
            else
              "#{name}[#{args.join(", ")}]"
            end
          end

          def subst(s)
            if free_variables.any? {|var| s.domain?(var) }
              _ = self.class.intern(
                name: name,
                args: args.map {|a| a.subst(s) }
              )
            else
              self
            end
          end

          def free_variables
            @fvs ||= Set.new().tap do |set|
              args.each do |type|
                set.merge(type.free_variables)
              end
            end
          end

          def each_child(&block)
            if block
              args.each(&block)
            else
              args.each
            end
          end

          include Helper::ChildrenLevel

          def level
            [0] + level_of_children(args)
          end

          def map_type(&block)
            args = self.args.map(&block)

            _ = self.class.new(name: self.name, args: self.args)
          end
        end

        class Singleton < Base
          # Returns a shared instance for the given name
          #
          # Note that the sharing is best-effort -- types constructed with `.new` are still
          # equal to the shared instances by the structural comparison.
          #
          def self.intern(name:)
            table = (@table ||= {}) #: Hash[RBS::TypeName, Singleton]
            table[name] ||= new(name: name)
          end

          def ==(other)
            return true if equal?(other)

            other.class == self.class &&
              other.name == name
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash
          end

          def to_s
            "singleton(#{name.to_s})"
          end

          include Helper::NoChild
        end

        class Instance < Applying
          def to_module
            Singleton.intern(name: name)
          end
        end

        class Interface < Applying
        end

        class Alias < Applying
        end
      end
    end
  end
end
