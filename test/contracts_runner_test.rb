require_relative "test_helper"

class ContractsRunnerTest < Minitest::Test
  include TestHelper
  include ShellHelper

  Contracts = Steep::Contracts
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
    class Foo
      attr_reader name: String?
      def helper: () -> Integer
    end
  RBS

  TRIGGERING_RUBY = <<~RUBY
    class Foo
      def helper
        name.size
      end
    end
  RUBY

  SAFE_RUBY = <<~RUBY
    class Foo
      def helper
        1 + 2
      end
    end
  RUBY

  def test_runner_infers_and_returns_contract
    in_tmpdir do
      write("sig/foo.rbs", FIXTURE_RBS)
      write("app/foo.rb", TRIGGERING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      contracts = Contracts::Runner.run(project)

      assert_equal 1, contracts.size
      assert_equal "Foo", contracts.first.type_name
      assert_equal :helper, contracts.first.method_name
      assert_equal :name, contracts.first.requires.first.expr.method
    end
  end

  def test_runner_write_creates_sidecar_with_inferred_content
    in_tmpdir do
      write("sig/foo.rbs", FIXTURE_RBS)
      write("app/foo.rb", TRIGGERING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Contracts::Runner.new(project)
      contracts = runner.run
      runner.write(contracts)

      sidecar = current_dir + Contracts::DEFAULT_SIDECAR_PATH
      assert sidecar.file?, "expected sidecar at #{sidecar}"

      reparsed = Contracts::Store.from_hash(YAML.safe_load(sidecar.read), source: sidecar.to_s)
      contract = reparsed.lookup_instance("Foo", :helper)
      refute_nil contract
      assert_equal :name, contract.requires.first.expr.method
    end
  end

  def test_runner_write_removes_sidecar_when_no_contracts
    in_tmpdir do
      write("sig/foo.rbs", FIXTURE_RBS)
      write("app/foo.rb", SAFE_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      sidecar = current_dir + Contracts::DEFAULT_SIDECAR_PATH
      sidecar.parent.mkpath
      sidecar.write("stale\n")

      runner = Contracts::Runner.new(project)
      contracts = runner.run
      runner.write(contracts)

      assert_empty contracts
      refute sidecar.file?, "expected stale sidecar to be removed when no contracts are inferred"
    end
  end

  def test_runner_is_idempotent
    in_tmpdir do
      write("sig/foo.rbs", FIXTURE_RBS)
      write("app/foo.rb", TRIGGERING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Contracts::Runner.new(project)
      first = runner.run
      runner.write(first)
      first_bytes = (current_dir + Contracts::DEFAULT_SIDECAR_PATH).read

      second = Contracts::Runner.run(project)
      runner.write(second)
      second_bytes = (current_dir + Contracts::DEFAULT_SIDECAR_PATH).read

      assert_equal first_bytes, second_bytes, "expected idempotent sidecar across two runs"
    end
  end

  def test_runner_uses_existing_sidecar_for_subsequent_runs
    in_tmpdir do
      write("sig/foo.rbs", FIXTURE_RBS)
      write("app/foo.rb", TRIGGERING_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Contracts::Runner.new(project)
      contracts = runner.run
      runner.write(contracts)
      assert_equal 1, contracts.size

      project2 = setup_project(steepfile: FIXTURE_STEEPFILE)
      assert_equal 1, project2.contracts.methods.size,
                   "expected Project#contracts to load the freshly-written sidecar"
    end
  end

  TRANSITIVE_RBS = <<~RBS
    class TBoard
      def user_name: () -> String
    end
    class TColumn
      attr_accessor board: TBoard?
      attr_accessor user_name: String?
      def initialize: () -> void
      def set_default_user_name: () -> void
      def save: () -> bool
    end
    class TCaller
      def self.run: () -> void
    end
  RBS

  # `set_default_user_name`'s body needs `self.board`; `save` calls it via
  # `self` without establishing board, so `save` inherits the requirement.
  def transitive_ruby(caller_sets_board:)
    setup = caller_sets_board ? "column.board = TBoard.new\n        " : ""
    <<~RUBY
      class TColumn
        def set_default_user_name
          self.user_name = board.user_name
        end
        def save
          set_default_user_name
          true
        end
      end
      class TCaller
        def self.run
          column = TColumn.new
          #{setup}column.save
        end
      end
    RUBY
  end

  def test_runner_propagates_precondition_transitively_and_enforces
    in_tmpdir do
      write("sig/t.rbs", TRANSITIVE_RBS)
      write("app/t.rb", transitive_ruby(caller_sets_board: true))
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      by_key = Contracts::Runner.run(project).each_with_object({}) { |c, h| h[c.key] = c }

      assert by_key.key?("TColumn#set_default_user_name")
      assert by_key.key?("TColumn#save"),
             "save must inherit the precondition transitively through the self-call"
      assert_equal :board, by_key["TColumn#save"].requires.first.expr.method

      # The only external caller sets board before `save`, so the whole chain
      # is enforced and the bodies narrow.
      assert by_key["TColumn#save"].enforced,
             "save enforced — its caller establishes board"
      assert by_key["TColumn#set_default_user_name"].enforced,
             "set_default_user_name enforced transitively once save guarantees board"
    end
  end

  def test_runner_transitive_contract_not_enforced_when_caller_omits_precondition
    in_tmpdir do
      write("sig/t.rbs", TRANSITIVE_RBS)
      write("app/t.rb", transitive_ruby(caller_sets_board: false))
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      by_key = Contracts::Runner.run(project).each_with_object({}) { |c, h| h[c.key] = c }

      assert by_key.key?("TColumn#save"), "save still inherits the requirement"
      refute by_key["TColumn#save"].enforced,
             "save not enforced — its caller does not establish board"
      refute by_key["TColumn#set_default_user_name"].enforced,
             "the chain stays unenforced so body errors surface"
    end
  end
end
