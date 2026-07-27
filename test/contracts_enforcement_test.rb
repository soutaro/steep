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
      delegation_registry: project.delegation_registry,
      constructor_bindings: project.constructor_binding_registry,
      return_forwarding: project.return_forwarding_registry,
      return_alias: project.return_alias_registry
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

  # felixefelip/steep#59: a precondition is enforced when its sole call site
  # proves the requirement through the receiver's *static type* — a
  # marker-refined intersection like `(Post & Post::Validated)` on which the
  # marker refines the required attribute to non-nil — even with no local read
  # to populate the pure-call flow cache. This exercises both halves of the
  # fix: the `Intersection` receiver being observed at all
  # (`precondition_target_type_names`), and being satisfied without a flow fact
  # (`precondition_holds?`'s static-type fallback).
  #
  # `greet`'s body has a trailing statement on purpose: a single-send body
  # (`def greet; user.name; end`) is a forward-delegate shape, which the
  # delegation inliner (#32) rewrites at the call site, bypassing the
  # precondition check entirely — so the contract would never be observed.
  # `Post::Validated` is a standalone marker (NOT `< Post`), mirroring what
  # rbs_rails emits: a subclass would make `(Post & Post::Validated)` simplify
  # to just `Post::Validated`, dropping the base member the contract lives on.
  # As a separate class the intersection is preserved, and `.user` resolves
  # against both members (`User?` from Post, `User` from the marker) to non-nil.
  MARKER_RBS = <<~RBS
    class User
      def name: () -> String
    end

    class Post
      def user: () -> User?
      def greet: () -> String
    end

    class Post::Validated
      def user: () -> User
    end
  RBS

  def test_enforced_when_sole_caller_has_marker_refined_receiver
    in_tmpdir do
      write("sig/marker.rbs", MARKER_RBS + <<~RBS)
        class Client
          def run: (Post & Post::Validated) -> void
        end
      RBS
      write("app/marker.rb", <<~RUBY)
        class Post
          def greet
            user.name
            "ok"
          end
        end

        class Client
          def run(post)
            post.greet
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      greet = contracts.find { |c| c.key == "Post#greet" }
      refute_nil greet, "expected a contract inferred for Post#greet"
      assert greet.enforced,
             "sole caller passes a (Post & Post::Validated) receiver whose marker makes self.user non-nil → enforced"

      typing = type_check_file(project, "app/marker.rb", store_of(contracts))
      assert_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "enforced contract narrows the body, so `user.name` is clean"
      assert_empty typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied),
                   "the marker-refined receiver satisfies the precondition — no PreconditionUnsatisfied"
    end
  end

  def test_not_enforced_when_caller_receiver_lacks_the_marker
    in_tmpdir do
      write("sig/marker.rbs", MARKER_RBS + <<~RBS)
        class Client
          def run: (Post) -> void
        end
      RBS
      write("app/marker.rb", <<~RUBY)
        class Post
          def greet
            user.name
            "ok"
          end
        end

        class Client
          def run(post)
            post.greet
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      greet = contracts.find { |c| c.key == "Post#greet" }
      refute_nil greet
      refute greet.enforced,
             "the caller's receiver is a bare Post (no marker) → self.user stays nilable → not enforced"

      typing = type_check_file(project, "app/marker.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced contract surfaces the hidden `user.name` error"
      refute_empty typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied),
                   "the caller that cannot prove the precondition gets a PreconditionUnsatisfied"
    end
  end

  # felixefelip/rbs_infer#71 (full pipeline): a self-call whose `self` a
  # *preceding postcondition* narrowed to a marker intersection — the real
  # `TagDestroy` shape, with the `.steep_postconditions.yml` sidecar INFERRED by
  # Steep (not hand-written). `set_xml` writes `@xml` non-nil, so the
  # postconditions Runner infers `self` → `Widget & Widget::AfterSetXml`; `run`
  # calls `set_xml` before `use_xml`, whose body dereferences `self.xml`. Through
  # the postconditions Runner → contracts Runner + Enforcement → check, the
  # inferred `not_nil xml` contract on `use_xml` must become enforced (its sole
  # call site is satisfied by the marker), so the body narrows and `xml.nodes`
  # type-checks. On the old code the intersection-self call site was neither
  # recognized nor discharged, so `enforced` stayed false and `xml.nodes`
  # surfaced a NoMethod. (`AfterSetXml` is declared in the RBS the way rbs_infer
  # emits its marker classes; the inferrer names the marker to match.)
  #
  # Since #94, method-entry facts carry IVARS, and this is exactly the shape they
  # cover: `use_xml`'s sole caller runs `set_xml` first, so the Runner records
  # `Widget#use_xml -> @xml: ::XmlDoc` and the body no longer errors. Contracts are
  # inferred FROM errors (`Contracts::Inferrer` reads `NoMethod` diagnostics), so no
  # contract is inferred here any more — not because the guarantee weakened, but
  # because a stronger mechanism discharges it before a diagnostic exists.
  #
  # The assertions below therefore pin the OUTCOME (`xml.nodes` clean, no
  # `PreconditionUnsatisfied`), which is what the test was always really about, plus
  # the entry fact that now delivers it. The contract path itself stays covered by
  # the shapes entry facts cannot reach — an EXTERNAL caller with a marker-refined
  # receiver (`test_enforced_when_sole_caller_has_marker_refined_receiver`) and the
  # constructor-chain tests below.
  def test_entry_facts_discharge_a_sole_self_caller_establishing_via_postcondition
    in_tmpdir do
      write("sig/marker_self.rbs", <<~RBS)
        class XmlDoc
          def nodes: () -> Array[Integer]
        end

        class Widget
          attr_reader xml: XmlDoc?
          def set_xml: () -> void
          def use_xml: () -> Array[Integer]
          def run: () -> void
        end

        class Widget::AfterSetXml
          def xml: () -> XmlDoc
        end
      RBS
      write("app/marker_self.rb", <<~RUBY)
        class Widget
          def set_xml
            @xml = XmlDoc.new
          end

          def use_xml
            xml.nodes
          end

          def run
            set_xml
            use_xml
          end
        end
      RUBY

      # Infer the postcondition sidecar with Steep itself, exactly as the real
      # `steep check` pipeline does before contract inference.
      pc_runner = Steep::Postconditions::Runner.new(setup_project(steepfile: STEEPFILE))
      pc_runner.write(pc_runner.run)
      reparsed = Steep::Postconditions::Store.from_hash(
        YAML.safe_load(pc_runner.output_path.read), source: "<test>"
      )
      set_xml_pc = reparsed.lookup_instance("Widget", :set_xml)
      refute_nil set_xml_pc, "expected a postcondition inferred for Widget#set_xml"
      assert_equal "::Widget & ::Widget::AfterSetXml", set_xml_pc.unconditional.self_type_string,
                   "the inferred marker name must match the RBS-declared marker class"

      # Fresh project so `project.postconditions` loads the just-written sidecar.
      project = setup_project(steepfile: STEEPFILE)

      # `run` calls `set_xml` before `use_xml`, so the sole call site establishes `@xml`
      # and the Runner records it as an entry fact of `use_xml` (#94).
      entry = reparsed.lookup_method_entry_facts("Widget", :use_xml)
      refute_nil entry, "expected method-entry facts inferred for Widget#use_xml"
      assert_equal "::XmlDoc", entry[:ivars][:"@xml"].to_s,
                   "the sole caller runs set_xml first → @xml is XmlDoc at use_xml's entry"

      contracts = Contracts::Runner.run(project)
      assert_nil contracts.find { |c| c.key == "Widget#use_xml" },
                 "the entry fact discharges the dereference before a NoMethod diagnostic exists, " \
                 "and contracts are inferred FROM those diagnostics → nothing left to require"

      typing = type_check_file(project, "app/marker_self.rb", store_of(contracts))
      assert_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "the entry fact narrows use_xml's body, so `xml.nodes` is clean"
      assert_empty typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied),
                   "run establishes @xml before use_xml → no PreconditionUnsatisfied"
    end
  end

  # felixefelip/steep#60: close a precondition across a constructor ivar-binding
  # and a `.new` argument site. `Proxy#probe` dereferences `self.owner.user`;
  # `owner` is `@owner`, bound in `initialize` to the constructor argument. When
  # the sole construction site hands `self` to `Proxy.new` from a getter
  # (`Post#assignments`) whose own caller has a marker-refined receiver, the
  # chain closes with no generics:
  #
  #   Proxy#probe  requires not_nil self.owner.user   (inferred)
  #     → self-call closure →  Proxy#initialize inherits it
  #     → `.new(self)` translation →  Post#assignments requires not_nil self.user
  #     → enforced at `post.assignments` (post: Post & Post::Validated) via #59
  #
  # The registry that maps `owner` → constructor arg index is built from source
  # by `Project#constructor_binding_registry` and consumed only in the
  # Enforcement pass, so `Contracts::Runner.run` exercises the whole chain.
  PROXY_RBS = <<~RBS
    class User
      def name: () -> String
    end

    class Post
      def user: () -> User?
      def assignments: () -> Proxy
    end

    class Post::Validated
      def user: () -> User
    end

    class Proxy
      def initialize: (Post owner) -> void
      def owner: () -> Post
      def probe: () -> String
    end
  RBS

  PROXY_APP = <<~RUBY
    class Proxy
      def initialize(owner)
        @owner = owner
        probe
      end

      def owner
        @owner
      end

      def probe
        owner.user.name
        "ok"
      end
    end

    class Post
      def assignments
        Proxy.new(self)
      end
    end
  RUBY

  def test_closes_precondition_through_constructor_and_new_site
    in_tmpdir do
      write("sig/proxy.rbs", PROXY_RBS + <<~RBS)
        class Client
          def run: (Post & Post::Validated) -> void
        end
      RBS
      write("app/proxy.rb", PROXY_APP + <<~RUBY)
        class Client
          def run(post)
            post.assignments
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)

      assignments = contracts.find { |c| c.key == "Post#assignments" }
      refute_nil assignments,
                 "the `.new(self)` site should synthesize a contract on the enclosing getter"
      assert_equal [[:not_nil, [:send, [:self], :user, []]]],
                   assignments.requires.map { |r| [:not_nil, expr_sig(r.expr)] },
                   "the translated obligation is `not_nil self.user` on Post#assignments"
      assert assignments.enforced,
             "the getter's caller passes a (Post & Post::Validated) receiver → enforced via #59"

      probe = contracts.find { |c| c.key == "Proxy#probe" }
      assert probe&.enforced,
             "with the chain closed, the proxy body's precondition is enforced"

      typing = type_check_file(project, "app/proxy.rb", store_of(contracts))
      assert_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "enforced contract narrows the body, so `owner.user.name` is clean"
    end
  end

  def test_does_not_close_when_construction_site_lacks_the_marker
    in_tmpdir do
      write("sig/proxy.rbs", PROXY_RBS + <<~RBS)
        class Client
          def run: (Post) -> void
        end
      RBS
      write("app/proxy.rb", PROXY_APP + <<~RUBY)
        class Client
          def run(post)
            post.assignments
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)

      assignments = contracts.find { |c| c.key == "Post#assignments" }
      refute_nil assignments, "the obligation still creates the contract"
      refute assignments.enforced,
             "the getter's caller passes a bare Post → self.user unproven → not enforced"

      probe = contracts.find { |c| c.key == "Proxy#probe" }
      refute probe&.enforced, "chain does not close → proxy body precondition unenforced"

      typing = type_check_file(project, "app/proxy.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced contract surfaces the hidden `owner.user.name` error"
    end
  end

  # Local mirror of Runner#expr_signature, for asserting a contract's requires.
  def expr_sig(expr)
    case expr
    when Contracts::Expr::SelfRef then [:self]
    when Contracts::Expr::Send then [:send, expr_sig(expr.receiver), expr.method, expr.chain]
    end
  end

  # felixefelip/steep#62 end-to-end: a deref through a local that projects a
  # self path (`record = build; record.post.user`, where `build` returns a
  # record whose `post` is `self.owner`) is rooted at `self.owner.user`,
  # enforced at an external `.create!` site via return forwarding
  # (`@post.assignments.owner` == `@post`), and narrowed in the body. Exercises
  # all three registries (constructor-binding, return-forwarding, return-alias).
  FORWARD_RBS = <<~RBS
    class User
      def name: () -> String
    end

    class Post
      def user: () -> User?
      def assignments: () -> Proxy
    end

    class Post::Validated
      def user: () -> User
    end

    class Record
      def post=: (Post) -> Post
      def post: () -> Post
    end

    class Proxy
      def initialize: (Post owner) -> void
      def owner: () -> Post
      def build: () -> Record
      def create_record: () -> Record
    end
  RBS

  FORWARD_APP = <<~RUBY
    class Proxy
      def initialize(owner)
        @owner = owner
      end

      def owner
        @owner
      end

      def build
        record = Record.new
        record.post = owner
        record
      end

      def create_record
        record = build
        record.post.user.name
        record
      end
    end

    class Post
      def assignments
        Proxy.new(self)
      end
    end
  RUBY

  def test_closes_deref_through_return_aliased_local_at_forwarded_site
    in_tmpdir do
      write("sig/fwd.rbs", FORWARD_RBS + <<~RBS)
        class Client
          def run: (Post & Post::Validated) -> void
        end
      RBS
      write("app/fwd.rb", FORWARD_APP + <<~RUBY)
        class Client
          def run(post)
            post.assignments.create_record
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      create = contracts.find { |c| c.key == "Proxy#create_record" }
      refute_nil create, "return-aliasing roots `record.post.user` at `self.owner.user`"
      assert_equal [[:not_nil, [:send, [:self], :owner, [:user]]]],
                   create.requires.map { |r| [:not_nil, expr_sig(r.expr)] }
      assert create.enforced,
             "the external `.create_record` site forwards `@post.assignments.owner` to @post → enforced"

      typing = type_check_file(project, "app/fwd.rb", store_of(contracts))
      assert_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "the body's `record.post.user.name` narrows via the alias"
    end
  end

  def test_does_not_close_forwarded_site_without_marker
    in_tmpdir do
      write("sig/fwd.rbs", FORWARD_RBS + <<~RBS)
        class Client
          def run: (Post) -> void
        end
      RBS
      write("app/fwd.rb", FORWARD_APP + <<~RUBY)
        class Client
          def run(post)
            post.assignments.create_record
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      create = contracts.find { |c| c.key == "Proxy#create_record" }
      refute_nil create
      refute create.enforced,
             "a bare Post receiver can't prove @post.user → not enforced"

      typing = type_check_file(project, "app/fwd.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced → the hidden `record.post.user.name` error surfaces"
    end
  end

  # felixefelip/steep#64 end-to-end: a real `before_validation` deref
  # `post.user.name` (two nilable hops, `self.post: Post?` and
  # `self.post.user: User?`) reached via `record.save` in a proxy. Gap 1 infers
  # both hops on `save`/`run_cb`; gap 2 translates `record.post.user` at
  # `record.save` through the alias (`record.post` == `self.owner`) to
  # `self.owner.user` on the proxy's `create`, discharged by forwarding at
  # `@post.assignments.create`.
  MULTIHOP_RBS = <<~RBS
    class MHUser
      def name: () -> String
    end

    class MHPost
      def user: () -> MHUser?
      def assignments: () -> MHProxy
    end

    class MHPost::Validated
      def user: () -> MHUser
    end

    class MHAssignment
      def post=: (MHPost) -> MHPost
      def post: () -> MHPost?
      def save: () -> bool
      def run_cb: () -> void
    end

    class MHProxy
      def initialize: (MHPost owner) -> void
      def owner: () -> MHPost
      def build: () -> MHAssignment
      def create: () -> MHAssignment
    end
  RBS

  MULTIHOP_APP = <<~RUBY
    class MHAssignment
      def save
        run_cb
        true
      end

      def run_cb
        post.user.name
      end
    end

    class MHProxy
      def initialize(owner)
        @owner = owner
      end

      def owner
        @owner
      end

      def build
        record = MHAssignment.new
        record.post = owner
        record
      end

      def create
        record = build
        record.save
        record
      end
    end

    class MHPost
      def assignments
        MHProxy.new(self)
      end
    end
  RUBY

  def test_closes_multihop_callback_deref_through_aliased_record_save
    in_tmpdir do
      write("sig/mh.rbs", MULTIHOP_RBS + <<~RBS)
        class MHClient
          def run: (MHPost & MHPost::Validated) -> void
        end
      RBS
      write("app/mh.rb", MULTIHOP_APP + <<~RUBY)
        class MHClient
          def run(post)
            post.assignments.create
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)

      save = contracts.find { |c| c.key == "MHAssignment#save" }
      refute_nil save
      sigs = save.requires.map { |r| expr_sig(r.expr) }
      assert_includes sigs, [:send, [:self], :post, []], "gap 1: the first nilable hop"
      assert_includes sigs, [:send, [:self], :post, [:user]], "gap 1: the deeper masked hop"
      assert save.enforced,
             "gap 2: `record.save` discharges it via the alias + forwarding at `@post.assignments.create`"

      typing = type_check_file(project, "app/mh.rb", store_of(contracts))
      assert_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "`run_cb`'s `post.user.name` narrows once `save` is enforced"
    end
  end

  def test_does_not_close_multihop_without_marker
    in_tmpdir do
      write("sig/mh.rbs", MULTIHOP_RBS + <<~RBS)
        class MHClient
          def run: (MHPost) -> void
        end
      RBS
      write("app/mh.rb", MULTIHOP_APP + <<~RUBY)
        class MHClient
          def run(post)
            post.assignments.create
          end
        end
      RUBY
      project = setup_project(steepfile: STEEPFILE)

      contracts = Contracts::Runner.run(project)
      save = contracts.find { |c| c.key == "MHAssignment#save" }
      refute_nil save
      refute save.enforced, "a bare Post construction site can't prove `@post.user`"

      typing = type_check_file(project, "app/mh.rb", store_of(contracts))
      refute_empty typing.errors.grep(Diagnostic::Ruby::NoMethod),
                   "unenforced → `post.user.name` still errors"
    end
  end
end
