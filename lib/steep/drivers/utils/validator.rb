module Steep
  module Drivers
    module Utils
      class Validator
        attr_reader :stdout
        attr_reader :stderr
        attr_reader :verbose

        def initialize(stdout:, stderr:, verbose:)
          @stdout = stdout
          @stderr = stderr
          @verbose = verbose
        end

        def run(env:, builder:, check:)
          result = true

          env.each do |sig|
            yield sig if block_given?

            case sig
            when AST::Signature::Interface
              yield_self do
                instance_name = TypeName::Interface.new(name: sig.name)
                instance_interface = builder.build(instance_name)

                args = instance_interface.params.map {|var| AST::Types::Var.fresh(var) }
                instance_type = AST::Types::Name.new_interface(name: sig.name, args: args)

                instance_interface.instantiate(type: instance_type,
                                               args: args,
                                               instance_type: instance_type,
                                               module_type: nil).validate(check)
              end

            when AST::Signature::Module
              yield_self do
                instance_name = TypeName::Instance.new(name: sig.name)
                instance_interface = builder.build(instance_name)
                instance_args = instance_interface.params.map {|var| AST::Types::Var.fresh(var) }

                module_name = TypeName::Module.new(name: sig.name)
                module_interface = builder.build(module_name)
                module_args = module_interface.params.map {|var| AST::Types::Var.fresh(var) }

                instance_type = AST::Types::Name.new_instance(name: sig.name, args: instance_args)
                module_type = AST::Types::Name.new_module(name: sig.name, args: module_args)

                stdout.puts "👀 Validating instance methods..." if verbose
                instance_interface.instantiate(type: instance_type,
                                               args: instance_args,
                                               instance_type: instance_type,
                                               module_type: module_type).validate(check)

                stdout.puts "👀 Validating class methods..." if verbose
                module_interface.instantiate(type: module_type,
                                             args: module_args,
                                             instance_type: instance_type,
                                             module_type: module_type).validate(check)
              end

            when AST::Signature::Class
              yield_self do
                instance_name = TypeName::Instance.new(name: sig.name)
                instance_interface = builder.build(instance_name)
                instance_args = instance_interface.params.map {|var| AST::Types::Var.fresh(var) }

                module_name = TypeName::Class.new(name: sig.name, constructor: nil)
                module_interface = builder.build(module_name)
                module_args = module_interface.params.map {|var| AST::Types::Var.fresh(var) }

                instance_type = AST::Types::Name.new_instance(name: sig.name, args: instance_args)
                module_type = AST::Types::Name.new_class(name: sig.name, args: module_args, constructor: nil)

                stdout.puts "👀 Validating instance methods..." if verbose
                instance_interface.instantiate(type: instance_type,
                                               args: instance_args,
                                               instance_type: instance_type,
                                               module_type: module_type).validate(check)

                stdout.puts "👀 Validating class methods..." if verbose
                module_interface.instantiate(type: module_type,
                                             args: module_args,
                                             instance_type: instance_type,
                                             module_type: module_type).validate(check)
              end
            end

          rescue Interface::Instantiated::InvalidMethodOverrideError => exn
            result = false
            stdout.puts "😱 #{exn.message}"
            exn.result.trace.each do |s, t|
              case s
              when Interface::Method
                stdout.puts "  #{s.name}(#{s.type_name}) <: #{t.name}(#{t.type_name})"
              when Interface::MethodType
                stdout.puts "  #{s.location.source} <: #{t.location.source} (#{s.location.name}:#{s.location.start_line})"
              else
                stdout.puts "  #{s} <: #{t}"
              end
            end
            stdout.puts "  🚨 #{exn.result.error.message}"
          end

          result
        end
      end
    end
  end
end
