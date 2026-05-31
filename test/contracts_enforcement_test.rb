require_relative "test_helper"

# Tests for felixefelip/steep#20: a precondition contract is only enforced when
# every static call site satisfies it AND at least one exists. When it is not
# enforced, the main check stops narrowing the body so the errors the
# precondition was hiding surface again.
class ContractsEnforcementTest < Minitest::Test
  include TestHelper
  include ShellHelper

  Contracts = Steep::Contracts
  Project = Steep::Project
  Diagnostic = Steep::Diagnostic
  Services = Steep::Services

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

  STEEPFILE = <<~STEEPFILE
    target :app do
      signature "sig"
      check "app"
    end
  STEEPFILE

  # Type-checks a single source file with the given contracts store and returns
  # the resulting Typing, so tests can inspect body diagnostics.
  def type_check_file(project, relative, store)
    target = project.targets.first
    loader = Project::Target.construct_env_loader(options: target.options, project: project)
    file_loader = Services::FileLoader.new(base_dir: project.base_dir)
    file_loader.each_path_in_patterns(target.signature_pattern) do |path|
      absolute = project.absolute_path(path)
      loader.add(path: absolute) if absolute.file?
    end
    status = Services::SignatureService.load_from(loader, implicitly_returns_nil: target.implicitly_returns_nil).status
    subtyping = status.subtyping

    absolute = project.absolute_path(Pathname(relative))
    source = Steep::Source.parse(absolute.read, path: absolute, factory: subtyping.factory)
    Services::TypeCheckService.type_check(
      source: source,
      subtyping: subtyping,
      constant_resolver: status.constant_resolver,
      cursor: nil,
      contracts: store,
      postconditions: project.postconditions,
      callbacks: project.callbacks,
      delegation_registry: project.delegation_registry
    )
  end

  def store_of(contracts)
    Contracts::Store.new(
      methods: contracts.each_with_object({}) { |c, h| h[c.key] = c },
      source: "<test>"
    )
  end

  FOO_RBS = <<~RBS
    class Foo
      attr_reader name: String?
      def helper: () -> Integer
      def good_caller: () -> void
      def bad_caller: () -> void
    end
  RBS

  def test_enforced_when_sole_caller_checks_precondition
    in_tmpdir do
      write("sig/foo.rbs", FOO_RBS)
      write("app/foo.rb", <<~RUBY)
        class Foo
          def helper
            name.size
          end

          def good_caller
            if name
              helper
            end
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      helper = contracts.find { |c| c.key == "Foo#helper" }
      refute_nil helper, "expected a contract inferred for Foo#helper"
      assert helper.enforced, "sole caller checks the precondition → contract is enforced"

      typing = type_check_file(project, "app/foo.rb", store_of(contracts))
      assert_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "enforced contract narrows the body, so `name.size` is clean"
    end
  end

  def test_not_enforced_when_a_caller_skips_the_check
    in_tmpdir do
      write("sig/foo.rbs", FOO_RBS)
      write("app/foo.rb", <<~RUBY)
        class Foo
          def helper
            name.size
          end

          def bad_caller
            helper
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      helper = contracts.find { |c| c.key == "Foo#helper" }
      refute_nil helper
      refute helper.enforced, "a caller skips the check → contract is not enforced"

      typing = type_check_file(project, "app/foo.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced contract surfaces the hidden body error"
      refute_empty typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied),
                   "the skipping caller still gets a PreconditionUnsatisfied"
    end
  end

  def test_mixed_callers_flag_only_the_failing_one
    in_tmpdir do
      write("sig/foo.rbs", FOO_RBS)
      write("app/foo.rb", <<~RUBY)
        class Foo
          def helper
            name.size
          end

          def good_caller
            if name
              helper
            end
          end

          def bad_caller
            helper
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      helper = contracts.find { |c| c.key == "Foo#helper" }
      refute_nil helper
      refute helper.enforced, "one caller skips the check → not enforced"

      typing = type_check_file(project, "app/foo.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced contract surfaces the hidden body error"
      assert_equal 1, typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied).size,
                   "only the caller that skips the check gets a PreconditionUnsatisfied"
    end
  end

  def test_not_enforced_when_no_static_call_sites
    in_tmpdir do
      write("sig/foo.rbs", FOO_RBS)
      write("app/foo.rb", <<~RUBY)
        class Foo
          def helper
            name.size
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      helper = contracts.find { |c| c.key == "Foo#helper" }
      refute_nil helper
      refute helper.enforced, "zero static call sites → contract is not enforced"

      typing = type_check_file(project, "app/foo.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced contract surfaces the hidden body error"
      assert_empty typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied),
                   "no call sites → no orphan PreconditionUnsatisfied"
    end
  end

  # Integration: the order_factory motivating case. A Rails action (no static
  # caller) whose body relies on an inferred precondition must surface the
  # hidden errors. Both `self.company.name` reads should error, not just the
  # one after reassignment.
  CONTROLLER_RBS = <<~RBS
    class Company
      def name: () -> String?
    end

    class Company::Validated < Company
      def name: () -> String
    end

    class CompaniesController
      def edit: () -> void
      attr_accessor company: (Company & Company::Validated) | Company
    end
  RBS

  def test_rails_action_without_callers_surfaces_body_errors
    in_tmpdir do
      write("sig/controller.rbs", CONTROLLER_RBS)
      write("app/companies_controller.rb", <<~RUBY)
        class CompaniesController
          def edit
            self.company.name.size

            self.company = Company.new
            self.company.name.size
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      edit = contracts.find { |c| c.key == "CompaniesController#edit" }
      refute_nil edit, "expected a contract inferred for CompaniesController#edit"
      refute edit.enforced, "edit has no static caller → contract is not enforced"

      typing = type_check_file(project, "app/companies_controller.rb", store_of(contracts))
      no_method_lines = typing.errors
        .grep(Diagnostic::Ruby::NoMethod)
        .map { |e| e.location.line }
        .sort
      assert_equal 2, no_method_lines.size,
                   "both `self.company.name.size` reads should error, got lines: #{no_method_lines}"
    end
  end
end
