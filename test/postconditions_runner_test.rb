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
      assert_equal "::PCRunnerController & ::PCRunnerController::AfterSetCompany",
                   entry.unconditional.self_type_string
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

  MAY_WRITE_RBS = <<~RBS
    class MWController
      @halted: bool

      def redirect_to: () -> void
      def guard: () -> void
      def wrap: () -> void
    end
  RBS

  # felixefelip/steep#68 (item 1): the effect is closed over the self-call
  # graph, so a method whose only "write" is a call to a writer still reports
  # it — through any depth, and through a block.
  MAY_WRITE_RUBY = <<~RUBY
    class MWController
      def redirect_to
        @halted = true
      end

      def guard
        redirect_to
      end

      def wrap
        [1].each do
          guard
        end
      end
    end
  RUBY

  def test_runner_closes_may_write_over_self_call_graph
    in_tmpdir do
      write("sig/mw.rbs", MAY_WRITE_RBS)
      write("app/mw.rb", MAY_WRITE_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      entries = Postconditions::Runner.run(project)
      by_method = entries.to_h { |e| [e.method_name, e] }

      # Direct write.
      assert_equal Set[:@halted], by_method[:redirect_to].may_write_ivars
      # One hop: guard -> redirect_to.
      assert_equal Set[:@halted], by_method[:guard].may_write_ivars
      # Two hops, the second through a block: wrap -> (block) guard -> redirect_to.
      assert_equal Set[:@halted], by_method[:wrap].may_write_ivars
    end
  end

  def test_runner_serializes_may_write_effect
    in_tmpdir do
      write("sig/mw.rbs", MAY_WRITE_RBS)
      write("app/mw.rb", MAY_WRITE_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      entry = reparsed.lookup_instance("MWController", :guard)
      refute_nil entry, "a method with only a may-write effect must still round-trip"
      assert_equal Set[:@halted], entry.may_write_ivars
    end
  end

  CR_RBS = <<~RBS
    class User
    end

    class CRBase
      @halted: bool
      def redirect_to: () -> void
    end

    class CRController < CRBase
      def current_user: () -> User?
      def authenticate_user: () -> void
    end
  RBS

  # felixefelip/steep#68 item 2: the guard halts through an INHERITED
  # `redirect_to`, so the gate is recorded `via: redirect_to` and the Runner
  # must resolve it — across the superclass boundary — to `@halted`.
  CR_RUBY = <<~RUBY
    class CRBase
      def redirect_to
        @halted = true
      end
    end

    class CRController < CRBase
      def authenticate_user
        unless current_user
          redirect_to
          return
        end
      end
    end
  RUBY

  CC_RBS = <<~RBS
    class User
    end

    class Current
      def self.user: () -> User?
      def self.user=: (User?) -> User?
    end

    class CCBase
      @halted: bool
      def redirect_to: () -> void
    end

    class CCController < CCBase
      def current_user: () -> User?
      def authenticate_user: () -> void
    end
  RBS

  CC_RUBY = <<~RUBY
    class CCBase
      def redirect_to
        @halted = true
      end
    end

    class CCController < CCBase
      def authenticate_user
        unless current_user
          redirect_to
          return
        end
        Current.user = current_user
      end
    end
  RUBY

  # felixefelip/steep#68 item 3: the constant-attribute fact round-trips and its
  # gate resolves through the inherited `redirect_to`, like the self-method one.
  def test_runner_serializes_conditional_const_return
    in_tmpdir do
      write("sig/cc.rbs", CC_RBS)
      write("app/cc.rb", CC_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      entry = reparsed.lookup_instance("CCController", :authenticate_user)
      refute_nil entry
      spec = entry.conditional_const_returns["Current.user"]
      refute_nil spec, "constant conditional return should survive gate resolution"
      assert_equal :@halted, spec[:gate_ivar]
      assert_equal "::User", spec[:type].to_s
    end
  end

  def test_runner_resolves_conditional_return_gate_through_inheritance
    in_tmpdir do
      write("sig/cr.rbs", CR_RBS)
      write("app/cr.rb", CR_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      entry = reparsed.lookup_instance("CRController", :authenticate_user)
      refute_nil entry
      spec = entry.conditional_returns[:current_user]
      refute_nil spec, "conditional return should survive gate resolution"
      assert_equal :@halted, spec[:gate_ivar]
      assert_equal "::User", spec[:type].to_s
    end
  end

  ME_RBS = <<~RBS
    class User
    end

    class Current
      def self.user: () -> User?
      def self.user=: (User?) -> User?
    end

    class MEController
      @performed: bool
      def current_user: () -> User?
      def redirect_to: () -> void
      def performed?: () -> bool
      def authenticate_user: () -> void
      def log_it: () -> void
      def __rbs_infer__run_index: () -> void
    end
  RBS

  ME_RUBY = <<~RUBY
    class MEController
      def redirect_to
        @performed = true
      end
      def performed?
        @performed
      end
      def authenticate_user
        unless current_user
          redirect_to
          return
        end
        Current.user = current_user
      end
      def log_it
      end
      def __rbs_infer__run_index
        authenticate_user
        return if performed?
        log_it
        return if performed?
      end
    end
  RUBY

  # felixefelip/steep#68 item 4: the runner shows `log_it` runs after
  # `authenticate_user`, so authenticate_user's proven facts (item 2 + 3) hold
  # at log_it's entry.
  def test_runner_infers_method_entry_facts_from_runner
    in_tmpdir do
      write("sig/me.rbs", ME_RBS)
      write("app/me.rb", ME_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      facts = reparsed.lookup_method_entry_facts("MEController", :log_it)
      refute_nil facts, "log_it should get authenticate_user's facts at entry"
      assert_equal "::User", facts[:self_methods][:current_user].to_s
      assert_equal "::User", facts[:consts]["Current.user"].to_s
    end
  end

  def test_runner_propagates_facts_transitively_to_the_second_hop
    in_tmpdir do
      write("sig/fp.rbs", <<~RBS)
        class User
        end
        class Current
          def self.user: () -> User?
          def self.user=: (User?) -> User?
        end
        class FPController
          @performed: bool
          def current_user: () -> User?
          def redirect_to: () -> void
          def performed?: () -> bool
          def authenticate_user: () -> void
          def one_hop: () -> void
          def two_hop: () -> void
          def __rbs_infer__run_index: () -> void
        end
      RBS
      write("app/fp.rb", <<~RUBY)
        class FPController
          def redirect_to
            @performed = true
          end
          def performed?
            @performed
          end
          def authenticate_user
            unless current_user
              redirect_to
              return
            end
            Current.user = current_user
          end
          def one_hop
            two_hop
          end
          def two_hop
          end
          def __rbs_infer__run_index
            authenticate_user
            return if performed?
            one_hop
            return if performed?
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)

      # First hop: `one_hop` is called directly from the runner, where the guard proved
      # `Current.user` — the one-hop propagation that already worked.
      one = reparsed.lookup_method_entry_facts("FPController", :one_hop)
      refute_nil one, "one_hop should get the guard's Current.user at entry"
      assert_equal "::User", one[:consts]["Current.user"].to_s

      # Second hop: `two_hop` is reached ONLY through `one_hop`. The fixpoint seeds `one_hop`
      # with its own entry fact, so it forwards `Current.user` to `two_hop`.
      two = reparsed.lookup_method_entry_facts("FPController", :two_hop)
      refute_nil two, "two_hop should inherit Current.user transitively through one_hop"
      assert_equal "::User", two[:consts]["Current.user"].to_s
    end
  end

  TC_RBS = <<~RBS
    class User
      def full_name: () -> String
    end

    class Current
      def self.user: () -> User?
      def self.user=: (User?) -> User?
      def self.author_name: () -> String?
      def self.instance: () -> Current
      def user=: (User?) -> void
      def author_name=: (String?) -> String?
    end

    class TCHost
      @halted: bool
      def current_user: () -> User?
      def redirect_to: () -> void
      def authenticate_user: () -> void
    end
  RBS

  TC_RUBY = <<~RUBY
    class Current
      def user=(value)
        @user = value
        self.author_name = value&.full_name
      end
      def self.user=(value)
        @user = value
        instance.user = value
      end
    end

    class TCHost
      def redirect_to
        @halted = true
      end
      def authenticate_user
        unless current_user
          redirect_to
          return
        end
        Current.user = current_user
      end
    end
  RUBY

  # felixefelip/steep#68 item 5: `Current.user = <non-nil>` also proves
  # `Current.author_name`, because the (delegated) instance setter establishes it.
  def test_runner_expands_transitive_const_returns
    in_tmpdir do
      write("sig/tc.rbs", TC_RBS)
      write("app/tc.rb", TC_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      entry = reparsed.lookup_instance("TCHost", :authenticate_user)
      refute_nil entry
      assert entry.conditional_const_returns.key?("Current.user")
      author = entry.conditional_const_returns["Current.author_name"]
      refute_nil author, "the setter's establishment should promote to a const return"
      assert_equal "::String", author[:type].to_s
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

  ALIAS_RBS = <<~RBS
    class PCUser
      def name: () -> String
    end
    class PCPost
      def user: () -> PCUser?
      def assignments: () -> PCProxy
    end
    class PCPost::Validated
      def user: () -> PCUser
    end
    class PCRecord
      def post=: (PCPost) -> PCPost
      def post: () -> PCPost
    end
    class PCProxy
      @cached: PCUser?
      def initialize: (PCPost owner) -> void
      def owner: () -> PCPost
      def build: () -> PCRecord
      def capture: () -> void
    end
    class PCAliasController
      @post: (PCPost & PCPost::Validated)
      def run: () -> void
    end
  RBS

  ALIAS_RUBY = <<~RUBY
    class PCProxy
      def initialize(owner)
        @owner = owner
      end

      def owner
        @owner
      end

      def build
        record = PCRecord.new
        record.post = owner
        record
      end

      def capture
        record = build
        record.post.user.name
        @cached = record.post.user
      end
    end

    class PCPost
      def assignments
        PCProxy.new(self)
      end
    end

    class PCAliasController
      def run
        @post.assignments.capture
      end
    end
  RUBY

  # felixefelip/steep#62: the postconditions pass must type-check with the
  # project's real return-alias registry. `PCProxy#capture` establishes
  # `@cached = record.post.user`, where `record = build` return-aliases
  # `record.post` to `self.owner`; with `capture` enforced (via forwarding at
  # `@post.assignments.capture`), that deref narrows to `::PCUser`, so `@cached`
  # is refined from its declared `PCUser?`. If the runner type-checks with an
  # empty registry the deref stays `(::PCUser | nil)` and no refinement is
  # emitted — the bug this guards.
  def test_runner_applies_return_alias_narrowing_to_ivar_refinement
    in_tmpdir do
      write("sig/alias.rbs", ALIAS_RBS)
      write("app/alias.rb", ALIAS_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      # Persist contracts so `PCProxy#capture` is enforced before the
      # postconditions pass reads them.
      contracts = Steep::Contracts::Runner.new(project)
      contracts.write(contracts.run)

      project2 = setup_project(steepfile: FIXTURE_STEEPFILE)
      entries = Postconditions::Runner.run(project2)

      capture = entries.find { |e| e.class_name == "PCProxy" && e.method_name == :capture }
      refute_nil capture, "expected a postcondition entry for PCProxy#capture"
      assert_equal "::PCUser", capture.ivars[:"@cached"]&.to_s,
                   "the return-aliased `record.post.user` should narrow to ::PCUser so @cached is refined"
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

  ARG_FACTS_RBS = <<~RBS
    class AFFoo
      def self.name: () -> String?
      def self.name=: (String?) -> void
    end
    class AFAge
      def self.value: () -> Integer?
      def self.value=: (Integer?) -> void
    end
    class AFDispatcher
      def show: (Symbol) -> void
    end
    class AFRun
      def run_name: () -> void
      def run_age: () -> void
    end
  RBS

  ARG_FACTS_RUBY = <<~RUBY
    class AFFoo
      def self.name
        @name
      end
      def self.name=(value)
        @name = value
      end
    end
    class AFAge
      def self.value
        @value
      end
      def self.value=(value)
        @value = value
      end
    end
    class AFDispatcher
      def show(which)
        case which
        when :name then AFFoo.name
        when :age  then AFAge.value
        end
      end
    end
    class AFRun
      def run_name
        AFFoo.name = "John Doe"
        AFDispatcher.new.show(:name)
      end
      def run_age
        AFAge.value = 42
        AFDispatcher.new.show(:age)
      end
    end
  RUBY

  def test_runner_partitions_entry_facts_by_literal_argument
    # Argument-sensitive entry facts (peça 3). `show` is called with `:name` from a site
    # where `AFFoo.name` is established, and with `:age` from a site where `AFAge.value`
    # is. The whole-method entry fact is the MEET over both sites, so it holds NEITHER.
    # Partitioning by the literal argument keeps each fact attached to the callers that
    # actually prove it.
    in_tmpdir do
      write("sig/af.rbs", ARG_FACTS_RBS)
      write("app/af.rb", ARG_FACTS_RUBY)
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)

      # The unconditional entry fact for `show` carries neither const — the meet drops both.
      unconditional = reparsed.lookup_method_entry_facts("AFDispatcher", :show)
      if unconditional
        refute unconditional[:consts].key?("AFFoo.name"), "the meet over both call sites cannot prove AFFoo.name"
        refute unconditional[:consts].key?("AFAge.value"), "the meet over both call sites cannot prove AFAge.value"
      end

      partitions = reparsed.lookup_argument_entry_facts("AFDispatcher", :show)
      assert_equal 2, partitions.size, "one partition per literal argument"

      by_pattern = partitions.to_h { |p| [p[:pattern], p] }

      name_partition = by_pattern[":name"]
      refute_nil name_partition
      assert_equal :which, name_partition[:param_name], "the call-site index resolves to the callee's param name"
      assert_equal "::String", name_partition[:consts]["AFFoo.name"].to_s
      refute name_partition[:consts].key?("AFAge.value"), "the :name partition must not carry the :age caller's fact"

      age_partition = by_pattern[":age"]
      refute_nil age_partition
      assert_equal :which, age_partition[:param_name]
      assert_equal "::Integer", age_partition[:consts]["AFAge.value"].to_s
      refute age_partition[:consts].key?("AFFoo.name"), "the :age partition must not carry the :name caller's fact"
    end
  end

  def test_runner_meets_argument_facts_across_call_sites_with_the_same_literal
    # Two callers pass `:name`, but only one establishes `AFFoo.name`. A partition is the
    # MEET over its own call sites, so the fact must be dropped — soundness is per-literal,
    # not per-caller.
    in_tmpdir do
      write("sig/af.rbs", ARG_FACTS_RBS)
      write("app/af.rb", <<~RUBY)
        #{ARG_FACTS_RUBY}
        class AFRun
          def run_name_unestablished
            AFDispatcher.new.show(:name)
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      partitions = reparsed.lookup_argument_entry_facts("AFDispatcher", :show)
      name_partition = partitions.find { |p| p[:pattern] == ":name" }

      assert_nil name_partition, "a :name caller that establishes nothing must drop the partition"
    end
  end

  def test_runner_drops_argument_facts_when_a_call_site_passes_a_non_literal
    # SOUNDNESS. A caller that passes a variable (`show(sym)`) establishes nothing and may
    # reach ANY branch at runtime — including `when :name`, whose partition claims
    # `AFFoo.name`. Since that argument cannot be pinned to a literal, no partition on that
    # parameter is provable and all of them must be dropped. Without this, one dynamic call
    # site silently invalidates the whole correlation.
    in_tmpdir do
      write("sig/af.rbs", <<~RBS)
        #{ARG_FACTS_RBS}
        class AFRun
          def run_dynamic: (Symbol) -> void
        end
      RBS
      write("app/af.rb", <<~RUBY)
        #{ARG_FACTS_RUBY}
        class AFRun
          def run_dynamic(sym)
            AFDispatcher.new.show(sym)
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.run

      assert_empty runner.argument_entry_facts,
                   "a non-literal call site must drop every partition on that parameter"
    end
  end

  def test_runner_keeps_argument_facts_for_a_different_parameter
    # The drop is per PARAMETER, not per method: an unpinned argument at one position must
    # not take down a partition proven at another.
    in_tmpdir do
      write("sig/af.rbs", <<~RBS)
        class AFFoo
          def self.name: () -> String?
          def self.name=: (String?) -> void
        end
        class AFTwo
          def show: (Symbol, Symbol) -> void
        end
        class AFRunTwo
          def run_a: (Symbol) -> void
          def run_b: (Symbol) -> void
        end
      RBS
      write("app/af.rb", <<~RUBY)
        class AFFoo
          def self.name
            @name
          end
          def self.name=(value)
            @name = value
          end
        end
        class AFTwo
          def show(first, second)
            case second
            when :name then AFFoo.name
            end
          end
        end
        class AFRunTwo
          def run_a(sym)
            AFFoo.name = "John Doe"
            AFTwo.new.show(sym, :name)
          end
          def run_b(sym)
            AFTwo.new.show(sym, :other)
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.run

      partitions = runner.argument_entry_facts["AFTwo#show"] || []
      params = partitions.map { |p| p[:param] }.uniq

      refute_includes params, :first, "the unpinned first parameter must have no partition"
      assert_includes params, :second, "the literal-pinned second parameter keeps its partition"
    end
  end

  def test_runner_drops_argument_facts_after_a_splat
    # A splat makes every following position unknowable — the literal `:name` written after
    # it could land on any parameter — so nothing past it may be pinned.
    in_tmpdir do
      write("sig/af.rbs", <<~RBS)
        class AFFoo
          def self.name: () -> String?
          def self.name=: (String?) -> void
        end
        class AFSplat
          def show: (*Symbol) -> void
        end
        class AFRunSplat
          def run: (Array[Symbol]) -> void
        end
      RBS
      write("app/af.rb", <<~RUBY)
        class AFFoo
          def self.name
            @name
          end
          def self.name=(value)
            @name = value
          end
        end
        class AFSplat
          def show(first, second)
            case second
            when :name then AFFoo.name
            end
          end
        end
        class AFRunSplat
          def run(list)
            AFFoo.name = "John Doe"
            AFSplat.new.show(*list, :name)
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.run

      assert_empty runner.argument_entry_facts["AFSplat#show"] || [],
                   "a literal written after a splat cannot be pinned to a parameter"
    end
  end

  IVAR_FACTS_RBS = <<~RBS
    class IVHost
      @name: String?
      @value: Integer?
      def run_name: () -> void
      def run_age: () -> void
      def show: (Symbol) -> void
      def clobber: () -> void
    end
  RBS

  def test_runner_partitions_ivar_facts_by_literal_argument
    # The ivar analogue of the const partitioning: each caller establishes a DIFFERENT ivar
    # before dispatching, so the whole-method meet proves neither, and only the per-literal
    # partition keeps each branch readable.
    in_tmpdir do
      write("sig/iv.rbs", IVAR_FACTS_RBS)
      write("app/iv.rb", <<~RUBY)
        class IVHost
          def run_name
            @name = 'John Doe'
            show(:name)
          end
          def run_age
            @value = 42
            show(:age)
          end
          def show(which)
            case which
            when :name then @name
            when :age then @value
            end
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.write(runner.run)

      reparsed = Postconditions::Store.from_hash(YAML.safe_load(runner.output_path.read), source: runner.output_path.to_s)
      partitions = reparsed.lookup_argument_entry_facts("IVHost", :show)
      by_pattern = partitions.to_h { |p| [p[:pattern], p] }

      name_partition = by_pattern[":name"]
      refute_nil name_partition
      assert_equal "::String", name_partition[:ivars][:@name].to_s
      refute name_partition[:ivars].key?(:@value), "the :name partition must not carry the :age caller's ivar"

      age_partition = by_pattern[":age"]
      refute_nil age_partition
      assert_equal "::Integer", age_partition[:ivars][:@value].to_s
      refute age_partition[:ivars].key?(:@name), "the :age partition must not carry the :name caller's ivar"
    end
  end

  def test_runner_drops_ivar_facts_across_a_cross_object_call
    # An ivar fact is about the CALLER's `self`. Dispatching on ANOTHER object reaches a
    # receiver whose ivars this flow says nothing about, so the partition must carry none.
    in_tmpdir do
      write("sig/iv.rbs", IVAR_FACTS_RBS)
      write("app/iv.rb", <<~RUBY)
        class IVHost
          def run_name
            @name = 'John Doe'
            IVHost.new.show(:name)
          end
          def run_age
            @value = 42
            IVHost.new.show(:age)
          end
          def show(which)
            case which
            when :name then @name
            when :age then @value
            end
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.run

      partitions = runner.argument_entry_facts["IVHost#show"] || []
      assert partitions.all? { |p| p[:ivars].empty? },
             "a cross-object call carries no ivar facts"
    end
  end

  def test_runner_drops_ivar_facts_written_by_an_intervening_call
    # `clobber` may write `@name`, so the narrowing established before it does not survive
    # to the dispatch — the may-write closure applied to the flow walk.
    in_tmpdir do
      write("sig/iv.rbs", IVAR_FACTS_RBS)
      write("app/iv.rb", <<~RUBY)
        class IVHost
          def clobber
            @name = nil
          end
          def run_name
            @name = 'John Doe'
            clobber
            show(:name)
          end
          def run_age
            @value = 42
            show(:age)
          end
          def show(which)
            case which
            when :name then @name
            when :age then @value
            end
          end
        end
      RUBY
      project = setup_project(steepfile: FIXTURE_STEEPFILE)

      runner = Postconditions::Runner.new(project)
      runner.run

      partitions = runner.argument_entry_facts["IVHost#show"] || []
      name_partition = partitions.find { |p| p[:pattern] == ":name" }

      refute name_partition && name_partition[:ivars].key?(:@name),
             "an ivar a callee may write cannot survive to the dispatch"
    end
  end
end
