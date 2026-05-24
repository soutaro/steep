require_relative "test_helper"

# Tests for the project-wide forward-delegation index used by
# `TypeConstruction#type_send` for chain narrowing
# (felixefelip/steep#32). Covers building, lookups, invalidation,
# and graceful handling of files that fail to parse.
class ProjectDelegationRegistryTest < Minitest::Test
  include TestHelper
  include ShellHelper

  Project = Steep::Project
  DelegationRegistry = Steep::Project::DelegationRegistry

  def dirs
    @dirs ||= []
  end

  def envs
    @envs ||= []
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

  def test_builds_registry_from_all_ruby_sources_in_target
    # Two source files in the target; both have delegation methods.
    # The registry indexes both.
    in_tmpdir do
      write("app/event.rb", <<~RUBY)
        class Event
          def venue_name
            venue.name
          end
        end
      RUBY
      write("app/ticket.rb", <<~RUBY)
        class Ticket
          def venue_name
            event.venue_name
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      registry = project.delegation_registry

      event_info = registry.lookup("Event", :venue_name)
      refute_nil event_info
      assert_equal :attr_send, event_info.receiver_kind
      assert_equal :venue, event_info.receiver_name
      assert_equal :name, event_info.delegate_method

      ticket_info = registry.lookup("Ticket", :venue_name)
      refute_nil ticket_info
      assert_equal :attr_send, ticket_info.receiver_kind
      assert_equal :event, ticket_info.receiver_name
      assert_equal :venue_name, ticket_info.delegate_method
    end
  end

  def test_lookup_normalizes_leading_double_colon
    # Callers (TypeConstruction) often pass absolute class names like
    # `"::Concerts::Ticket"`. The registry stores logical names without
    # the leading `::`; lookup strips it for compatibility.
    in_tmpdir do
      write("app/foo.rb", <<~RUBY)
        module Concerts
          class Ticket
            def venue_name
              event.venue_name
            end
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      registry = project.delegation_registry
      info = registry.lookup("::Concerts::Ticket", :venue_name)
      refute_nil info, "expected ::-prefixed lookup to resolve"
      assert_equal :event, info.receiver_name
    end
  end

  def test_lookup_returns_nil_for_unknown_class
    in_tmpdir do
      write("app/foo.rb", "class Foo\n  def bar; end\nend\n")
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      assert_nil project.delegation_registry.lookup("DoesNotExist", :anything)
    end
  end

  def test_skips_files_with_syntax_errors
    # A malformed file shouldn't blow up the whole registry build —
    # other valid files still produce entries.
    in_tmpdir do
      write("app/broken.rb", "class Foo\n  def bar(\nend\n") # syntax error
      write("app/ticket.rb", <<~RUBY)
        class Ticket
          def venue_name
            event.venue_name
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      registry = project.delegation_registry
      refute_nil registry.lookup("Ticket", :venue_name)
    end
  end

  def test_invalidation_rebuilds_from_disk
    # The registry caches by default; invalidating drops the cache
    # so the next access re-reads source files. Verifies the
    # invalidate_delegation_registry! hook works.
    in_tmpdir do
      write("app/ticket.rb", <<~RUBY)
        class Ticket
          def venue_name
            event.venue_name
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      first = project.delegation_registry
      assert_same first, project.delegation_registry, "expected cached registry"

      project.invalidate_delegation_registry!
      second = project.delegation_registry
      refute_same first, second, "expected a fresh registry after invalidation"
      refute_nil second.lookup("Ticket", :venue_name)
    end
  end

  def test_empty_project_yields_empty_registry
    in_tmpdir do
      write("app/.keep", "")
      project = setup_project(steepfile: FIXTURE_STEEPFILE)
      registry = project.delegation_registry
      assert registry.empty?
    end
  end
end
