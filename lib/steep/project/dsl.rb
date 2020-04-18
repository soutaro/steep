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
        attr_reader :vendor_dir
        attr_reader :strictness_level

        def initialize(name, sources: [], libraries: [], signatures: [], ignored_sources: [])
          @name = name
          @sources = sources
          @libraries = libraries
          @signatures = signatures
          @ignored_sources = ignored_sources
          @vendor_dir = nil
          @strictness_level = :default
        end

        def initialize_copy(other)
          @name = other.name
          @sources = other.sources.dup
          @libraries = other.libraries.dup
          @signatures = other.signatures.dup
          @ignored_sources = other.ignored_sources.dup
          @vendor_dir = other.vendor_dir
          @strictness_level = other.strictness_level
        end

        def check(*args)
          sources.push(*args)
        end

        def ignore(*args)
          ignored_sources.push(*args)
        end

        def library(*args)
          libraries.push(*args)
        end

        def typing_options(level)
          @strictness_level = level
        end

        def signature(*args)
          signatures.push(*args)
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
          Steep.logger.error "`no_builtin!` in Steepfile is deprecated and ignored. Use `vendor` instead."
        end

        def vendor(dir = "vendor/sigs", stdlib: nil, gems: nil)
          if stdlib || gems
            @vendor_dir = [
              stdlib&.yield_self {|x| Pathname(x) },
              gems&.yield_self {|x| Pathname(x) }
            ]
          else
            @vendor_dir = Pathname(dir)
          end
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
            options.libraries.push(*target.libraries)

            case target.strictness_level
            when :strict
              options.apply_strict_typing_options!
            when :lenient
              options.apply_lenient_typing_options!
            end

            case target.vendor_dir
            when Array
              options.vendored_stdlib_path = target.vendor_dir[0]
              options.vendored_gems_path = target.vendor_dir[1]
            when Pathname
              options.vendored_stdlib_path = target.vendor_dir + "stdlib"
              options.vendored_gems_path = target.vendor_dir + "gems"
            end
          end
        ).tap do |target|
          project.targets << target
        end
      end
    end
  end
end
