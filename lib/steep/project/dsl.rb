module Steep
  class Project
    class DSL
      class TargetDSL
        attr_reader :name
        attr_reader :sources
        attr_reader :libraries
        attr_reader :signatures
        attr_reader :ignored_sources
        attr_reader :no_builtin

        def initialize(name, sources: [], libraries: [], signatures: [], ignored_sources: [])
          @name = name
          @sources = sources
          @libraries = libraries
          @signatures = signatures
          @ignored_sources = ignored_sources
          @no_builtin = false
        end

        def initialize_copy(other)
          @name = other.name
          @sources = other.sources.dup
          @libraries = other.libraries.dup
          @signatures = other.signatures.dup
          @ignored_sources = other.ignored_sources.dup
          @no_builtin = other.no_builtin
        end

        def check(*args)
          sources.push *args
        end

        def ignore(*args)
          ignored_sources.push *args
        end

        def library(*args)
          libraries.push *args
        end

        def signature(*args)
          signatures.push *args
        end

        def update(name: self.name, sources: self.sources, libraries: self.libraries, ignored_sources: self.ignored_sources, signatures: self.signatures)
          self.class.new(
            name,
            sources: sources,
            libraries: libraries,
            signatures: signatures,
            ignored_sources: ignored_sources
          )
        end

        def no_builtin!(value = true)
          @no_builtin = no_builtin
        end
      end

      attr_reader :project

      @@templates = {
        gemfile: TargetDSL.new(:gemfile).tap do |target|
          target.check "Gemfile"
          target.library "gemfile"
        end
      }

      def self.templates
        @@templates
      end

      def initialize(project:)
        @project = project
        @global_signatures = []
      end

      def self.register_template(name, target)
        templates[name] = target
      end

      def self.parse(project, code, filename: "Steepfile")
        self.new(project: project).instance_eval(code, filename)
      end

      def target(name, template: nil, &block)
        target = if template
                   self.class.templates[template]&.dup&.update(name: name) or
                     raise "Unknown template: #{template}, available templates: #{@@templates.keys.join(", ")}"
                 else
                   TargetDSL.new(name)
                 end

        target.instance_eval(&block) if block_given?

        Project::Target.new(
          name: target.name,
          source_patterns: target.sources,
          ignore_patterns: target.ignored_sources,
          signature_patterns: target.signatures,
          options: Options.new.tap do |options|
            options.libraries.push *target.libraries
            options.no_builtin = true if target.no_builtin
          end
        ).tap do |target|
          project.targets << target
        end
      end
    end
  end
end
