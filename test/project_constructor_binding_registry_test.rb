require_relative "test_helper"

# Tests for the project-wide constructor reader→parameter index consumed by
# `TypeConstruction` at `.new` call sites (felixefelip/steep#60). Covers
# building from source, lookups, and invalidation.
class ProjectConstructorBindingRegistryTest < Minitest::Test
  include TestHelper
  include ShellHelper

  Project = Steep::Project
  ConstructorBindingRegistry = Steep::Project::ConstructorBindingRegistry

  def dirs
    @dirs ||= []
  end

  def write(relative, content)
    path = current_dir + relative
    path.parent.mkpath
    path.write(content)
    path
  end

  def setup_project(steepfile:)
    write("Steepfile", steepfile)
    project = Project.new(steepfile_path: current_dir + "Steepfile")
    Project::DSL.parse(project, steepfile, filename: (current_dir + "Steepfile").to_s)
    project
  end

  FIXTURE_STEEPFILE = <<~STEEPFILE
    target :app do
      signature "sig"
      check "app"
    end
  STEEPFILE

  def test_builds_and_looks_up_bindings_from_sources
    in_tmpdir do
      write("app/proxy.rb", <<~RUBY)
        class Proxy
          def initialize(klass, owner)
            @owner = owner
          end
          def owner = @owner
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)
      registry = ConstructorBindingRegistry.build(project)

      assert_equal 1, registry.lookup("Proxy", :owner)
      assert_equal 1, registry.lookup("::Proxy", :owner), "leading `::` is stripped"
      assert_nil registry.lookup("Proxy", :missing)
      assert_nil registry.lookup("Nope", :owner)
      assert_equal({ owner: 1 }, registry.bindings_for("Proxy"))
    end
  end

  def test_rebuilt_after_invalidation
    in_tmpdir do
      write("app/proxy.rb", <<~RUBY)
        class Proxy
          def initialize(owner)
            @owner = owner
          end
          def owner = @owner
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)
      assert_equal 0, project.constructor_binding_registry.lookup("Proxy", :owner)

      write("app/proxy.rb", <<~RUBY)
        class Proxy
          def initialize(klass, owner)
            @owner = owner
          end
          def owner = @owner
        end
      RUBY
      project.invalidate_constructor_binding_registry!
      assert_equal 1, project.constructor_binding_registry.lookup("Proxy", :owner),
                   "the index reflects the new constructor arity after invalidation"
    end
  end
end
