require_relative "test_helper"

class PostconditionsRunnerTest < Minitest::Test
  include TestHelper
  include ShellHelper

  Postconditions = Steep::Postconditions
  Project = Steep::Project

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

  FIXTURE_RBS = <<~RBS
    class PCRunnerCompany
      def self.find: (Integer) -> (PCRunnerCompany & PCRunnerCompany::Validated)
    end

    module PCRunnerCompany::Validated
    end

    class PCRunnerController
      @company: (PCRunnerCompany & PCRunnerCompany::Validated) | PCRunnerCompany

      def set_company: () -> (PCRunnerCompany & PCRunnerCompany::Validated)
    end
  RBS

  NARROWING_RUBY = <<~RUBY
    class PCRunnerController
      def set_company
        @company = PCRunnerCompany.find(1)
      end
    end
  RUBY

  SAFE_RUBY = <<~RUBY
    class PCRunnerController
      def set_company
        1 + 2
      end
    end
  RUBY

  def test_runner_infers_unconditional_ivar_entry
    in_tmpdir do
      write("sig/company.rbs", FIXTURE_RBS)
      write("app/controller.rb", NARROWING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      entries = Postconditions::Runner.run(project)

      assert_equal 1, entries.size
      entry = entries.first
      assert_equal "PCRunnerController", entry.class_name
      assert_equal :set_company, entry.method_name
      refute entry.singleton
      assert_equal [:"@company"], entry.ivars.keys
      assert_equal "(::PCRunnerCompany & ::PCRunnerCompany::Validated)", entry.ivars[:"@company"].to_s
    end
  end

  def test_runner_write_creates_sidecar_with_inferred_content
    in_tmpdir do
      write("sig/company.rbs", FIXTURE_RBS)
      write("app/controller.rb", NARROWING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      entries = runner.run
      runner.write(entries)

      sidecar = runner.output_path
      assert sidecar.file?, "expected sidecar at #{sidecar}"

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(sidecar.read), source: sidecar.to_s)
      entry = reparsed.lookup_instance("PCRunnerController", :set_company)
      refute_nil entry, "expected entry to round-trip through the loader"
      refute_nil entry.unconditional, "expected unconditional branch"
      assert_equal({ :"@company" => "(::PCRunnerCompany & ::PCRunnerCompany::Validated)" }, entry.unconditional.ivar_type_strings)
    end
  end

  def test_runner_write_removes_sidecar_when_no_entries
    in_tmpdir do
      write("sig/company.rbs", FIXTURE_RBS)
      write("app/controller.rb", SAFE_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      sidecar = runner.output_path
      sidecar.parent.mkpath
      sidecar.write("stale\n")

      entries = runner.run
      runner.write(entries)

      assert_empty entries
      refute sidecar.file?, "expected stale sidecar to be removed when no entries are inferred"
    end
  end

  def test_runner_is_idempotent
    in_tmpdir do
      write("sig/company.rbs", FIXTURE_RBS)
      write("app/controller.rb", NARROWING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      first = runner.run
      runner.write(first)
      first_bytes = runner.output_path.read

      second = Postconditions::Runner.run(project)
      runner.write(second)
      second_bytes = runner.output_path.read

      assert_equal first_bytes, second_bytes, "expected idempotent sidecar across two runs"
    end
  end

  def test_runner_sidecar_consumable_by_consumer_on_next_run
    # The whole point of the runner: write a sidecar that the *next*
    # project load picks up and applies. Verifies the loop closes:
    # narrow detected → written → re-loaded → available at the new
    # project's `postconditions` store.
    in_tmpdir do
      write("sig/company.rbs", FIXTURE_RBS)
      write("app/controller.rb", NARROWING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      entries = runner.run
      runner.write(entries)

      project2 = setup_project(steepfile: FIXTURE_STEEPFILE)
      entry = project2.postconditions.lookup_instance("PCRunnerController", :set_company)
      refute_nil entry, "expected Project#postconditions to load the freshly-written sidecar"
      assert_equal "(::PCRunnerCompany & ::PCRunnerCompany::Validated)",
                   entry.unconditional.ivar_type_strings[:"@company"]
    end
  end
end
