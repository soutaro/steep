module Steep
  module TypeInference
    class TypeEnvBuilder
      module Command
        class AnnotationsBase
          attr_reader :annotations

          def initialize(annotations)
            @annotations = annotations
          end
        end

        class RBSBase
          attr_reader :factory

          attr_reader :environment

          def initialize(factory)
            @factory = factory
            @environment = factory.env
          end
        end

        class ImportLocalVariableAnnotations < AnnotationsBase
          attr_reader :on_duplicate

          def initialize(annotations)
            super
            @merge = false
            @on_duplicate = nil
          end

          def merge!(merge = true)
            @merge = merge
            self
          end

          def on_duplicate!(&block)
            @on_duplicate = block
            self
          end

          def call(env)
            local_variable_types = annotations.var_type_annotations.each.with_object({}) do |pair, hash|
              name, annotation = pair
              annotation_type = annotations.absolute_type(annotation.type) || annotation.type

              if current_type = env[name]
                on_duplicate&.call(name, current_type, annotation_type)
                hash[name] = [annotation_type, annotation_type]
              else
                hash[name] = [annotation_type, annotation_type]
              end
            end

            if @merge
              env.merge(local_variable_types: local_variable_types)
            else
              env.update(local_variable_types: local_variable_types)
            end
          end
        end

        class ImportInstanceVariableAnnotations < AnnotationsBase
          def call(env)
            ivar_types = annotations.ivar_type_annotations.transform_values do |annotation|
              annotations.absolute_type(annotation.type) || annotation.type
            end

            if @merge
              env.merge(instance_variable_types: ivar_types)
            else
              env.update(instance_variable_types: ivar_types)
            end
          end

          def merge!(merge = true)
            @merge = merge
            self
          end
        end

        class ImportGlobalDeclarations < RBSBase
          def call(env)
            global_types = environment.global_decls.transform_values do |decl|
              factory.type(decl.decl.type)
            end

            env.update(global_types: global_types)
          end
        end

        class ImportInstanceVariableDefinition
          attr_reader :definition

          attr_reader :factory

          def initialize(definition, factory)
            @definition = definition
            @factory = factory
          end

          def call(env)
            return env unless definition

            instance_variable_types = definition.instance_variables.transform_values do |ivar|
              factory.type(ivar.type)
            end

            env.update(instance_variable_types: instance_variable_types)
          end
        end

        class ImportConstantAnnotations < AnnotationsBase
          def call(env)
            constant_types = annotations.const_type_annotations.transform_values do |const|
              annotations.absolute_type(const.type) || const.type
            end

            env.update(constant_types: constant_types)
          end
        end
      end

      attr_reader :commands

      def initialize(*commands)
        @commands = commands.compact
      end

      def build(type_env)
        commands.inject(type_env) do |env, command|
          command.call(env)
        end
      end
    end
  end
end
