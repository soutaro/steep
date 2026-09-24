require_relative "test_helper"

# @rbs use Steep::*

class InteractionWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol
  InteractionWorker = Server::InteractionWorker
  ContentChange = Services::ContentChange

  include Server::CustomMethods

  # @rbs (Server::InteractionWorker) { (Thread) -> void } -> void
  def run_worker(worker)
    t = Thread.new do
      worker.run()
    end

    yield t

  ensure
    t.join

    reader_pipe[1].close
    writer_pipe[1].close
  end

  def dirs
    @dirs ||= []
  end

  def test_handle_request_file_load
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.handle_request(
        {
          method: FileLoad::METHOD,
          params: {
            content: { "lib/hello.rb" => "1 + true" }
          }
        }
      )

      refute_empty worker.buffered_changes
    end
  end

  def test_handle_request_hover
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.handle_request(
        {
          id: 123,
          method: Hover::METHOD,
          params: {
            uri: "#{file_scheme}#{current_dir}/lib/hello.rb",
            position: { line: 1, character: 2 }
          }
        }
      )

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      q[0].tap do |job|
        assert_instance_of InteractionWorker::HoverJob, job
        assert_equal 123, job.id
        assert_equal Pathname("lib/hello.rb"), job.path
        assert_equal 2, job.line
        assert_equal 2, job.column
      end
    end
  end

  def test_handle_source_symbol_request
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.handle_request(
        {
          id: 123,
          method: Source__Symbol::METHOD,
          params: {
            uri: "#{file_scheme}#{current_dir}/lib/hello.rb",
            position: { line: 1, character: 2 }
          }
        }
      )

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      q[0].tap do |job|
        assert_instance_of InteractionWorker::SourceSymbolJob, job
        assert_equal current_dir + "lib/hello.rb", job.path
        assert_equal 2, job.line
        assert_equal 2, job.column
      end
    end
  end

  def test_process_source_symbol_job
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("sig/customer.rbs") => [ContentChange.string(<<RBS)],
class Customer
  attr_accessor name: String
end
RBS
          Pathname("lib/main.rb") => [ContentChange.string(<<RUBY)]
customer = Customer.new()
customer.name = "Soutaro"
RUBY
        }
      )

      # `Customer` in `Customer.new()` -- the constant, and the type of the expression is its singleton
      result = worker.process_source_symbol(InteractionWorker::SourceSymbolJob.new(id: 1, path: current_dir + "lib/main.rb", line: 1, column: 14))
      assert_equal({ constant: "::Customer", type: "singleton(::Customer)" }, result)

      # `name` in `customer.name = ...` -- the method, and the type of the assignment is the value
      result = worker.process_source_symbol(InteractionWorker::SourceSymbolJob.new(id: 2, path: current_dir + "lib/main.rb", line: 2, column: 10))
      assert_equal({ method_names: ["::Customer#name="], type: "::String" }, result)

      # `customer` -- nothing is written, and the type of the variable is Customer
      result = worker.process_source_symbol(InteractionWorker::SourceSymbolJob.new(id: 3, path: current_dir + "lib/main.rb", line: 2, column: 2))
      assert_equal({ type: "::Customer" }, result)
    end
  end

  def test_handle_hover_job_success
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo = 1 + 2
bar = foo.to_s
RUBY
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 1))

      assert_equal(
        {
          target: "lib",
          range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
          content: { kind: "variable", name: "foo", type: "::Integer" }
        },
        response
      )

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 2, column: 11))

      assert_equal({ start: { line: 1, character: 10 }, end: { line: 1, character: 14 } }, response[:range])
      assert_equal(
        {
          kind: "method_call",
          return_type: "::String",
          special: false,
          error: false,
          method_types: ["(?::int base) -> ::String"],
          methods: ["::Integer#to_s"]
        },
        response[:content]
      )
    end
  end

  def test_handle_hover_job__definition_and_constant
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<RBS)],
class Foo
  def self.bar: () -> Integer
end
RBS
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
class Foo
  def self.bar
    Foo
  end
end
RUBY
        }
      ) {}

      # `bar` in `def self.bar`
      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 2, column: 12))
      assert_equal(
        { kind: "definition", method: "::Foo.bar", method_type: "() -> ::Integer", method_types: ["() -> ::Integer"] },
        response[:content]
      )

      # `Foo` in the body
      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 3, column: 5))
      assert_equal({ kind: "constant", name: "::Foo" }, response[:content])
    end
  end

  def test_handle_alias_hover_job_success_on_rbs
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# here is your comments
type foo = Integer | String

class FooBar
  def f: (foo) -> void
end
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 5, column: 11))

      assert_equal "lib", response[:target]
      assert_equal({ start: { line: 4, character: 10 }, end: { line: 4, character: 13 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::foo" }, response[:content])
    end
  end

  def test_handle_interface_hover_job_success_on_rbs
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# here is your comments
interface _Fooable
  def foo: () -> nil
end

class Test
  def foo: (_Fooable) -> nil
end
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 7, column: 13))

      assert_equal({ start: { line: 6, character: 12 }, end: { line: 6, character: 20 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::_Fooable" }, response[:content])
    end
  end

  def test_handle_class_hover_job_success_on_rbs
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# here is your comments
class Foo [T] < Parent[T] end
class Parent [in T] end
module Hoge end
class Qux
  @foo: Foo[Hoge]
end
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 6, column: 10))

      assert_equal({ start: { line: 5, character: 8 }, end: { line: 5, character: 11 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::Foo" }, response[:content])
    end
  end

  def test_handle_class_hover_strip_html_comment
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# <!-- HTML comment here -->
# This is comment content
class Foo[T] end

type hello = Foo[String]
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 5, column: 15))

      assert_equal({ start: { line: 4, character: 13 }, end: { line: 4, character: 16 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::Foo" }, response[:content])
    end
  end

  def test_handle_hover_invalid
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo = 1 + 2
bar = foo.
RUBY
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 1))
      assert_nil response
    end
  end

  def test_handle_completion_request
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.service.update(
        changes: {
          Pathname("lib/hello.rb") => [ContentChange.string(<<RUBY)]
foo = 100
foo + "bar"
RUBY
        }
      ) {}

      response = worker.process_completion(
        InteractionWorker::CompletionJob.new(
          path: Pathname("lib/hello.rb"),
          line: 3,
          column: 0,
          trigger: nil
        )
      )

      assert_equal "lib", response[:target]
      refute response[:incomplete]
      assert_any!(response[:items]) do |item|
        assert_equal "method", item[:kind]
        assert_equal "puts", item[:name]
        assert_equal ["::Kernel#puts"], item[:methods]
        assert_equal ["(*::_ToS) -> nil"], item[:method_types]
        assert_equal({ start: { line: 2, character: 0 }, end: { line: 2, character: 0 } }, item[:range])
      end
    end
  end

  def test_handle_completion_request_inline
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib/inline.rb", inline: true
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.service.update(
        changes: {
          Pathname("lib/inline.rb") => [ContentChange.string(<<RUBY)]
class Foo
  # @rbs @name: String

  # @rbs () -> void
  def hello
    @name
  end
end
RUBY
        }
      ) {}

      response = worker.process_completion(
        InteractionWorker::CompletionJob.new(
          path: Pathname("lib/inline.rb"),
          line: 6,
          column: 5,
          trigger: nil
        )
      )

      assert_any!(response[:items]) do |item|
        assert_equal "instance_variable", item[:kind]
        assert_equal "@name", item[:name]
        assert_equal "::String", item[:type]
      end
    end
  end

  def test_completion_on_signature
    in_tmpdir do
      in_tmpdir do
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
        worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

        worker.service.update(
          changes:{
            Pathname("sig/hello.rbs") => [ContentChange.string(<<~RBS)]
              class Hoge end
              class Qux
                @foo: H
              end
            RBS
          }
        ) {}

        response = worker.process_completion(
          InteractionWorker::CompletionJob.new(
            path: Pathname("sig/hello.rbs"),
            line: 3,
            column: 9,
            trigger: nil
          )
        )

        assert_equal "lib", response[:target]
        refute response[:incomplete]

        assert_any!(response[:items]) do |item|
          assert_equal "type_name", item[:kind]
          assert_equal "Hash", item[:name]
          assert_equal "::Hash", item[:full_name]
          assert_equal({ start: { line: 2, character: 8 }, end: { line: 2, character: 9 } }, item[:range])
        end

        assert_any!(response[:items]) do |item|
          assert_equal "type_name", item[:kind]
          assert_equal "Hoge", item[:name]
          assert_equal "::Hoge", item[:full_name]
        end

        assert_any!(response[:items]) do |item|
          assert_equal "builtin_type", item[:kind]
          assert_equal "untyped", item[:name]
          assert_equal({ start: { line: 2, character: 8 }, end: { line: 2, character: 9 } }, item[:range])
        end
      end
    end
  end

  def test_signature_help
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<RBS)],
class Foo
  def foo: (String name, ?Integer size) -> void
         | () -> void
end
RBS
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
Foo.new.foo("hello", 3)
RUBY
        }
      ) {}

      response = worker.process_signature_help(InteractionWorker::SignatureHelpJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 21))

      refute response[:syntax_error]
      response[:signature_help].tap do |help|
        assert_equal "lib", help[:target]
        assert_equal 0, help[:active_signature]
        assert_equal(
          [
            { method_type: "(::String, ?::Integer) -> void", parameters: ["::String", "?::Integer"], active_parameter: 1, method: "::Foo#foo" },
            { method_type: "() -> void", parameters: [], active_parameter: -1, method: "::Foo#foo" }
          ],
          help[:signatures]
        )
      end

      # Outside of the arguments of a call
      response = worker.process_signature_help(InteractionWorker::SignatureHelpJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 1))
      assert_equal({ signature_help: nil, syntax_error: false }, response)
    end
  end

  def test_signature_help__syntax_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo(1,
RUBY
        }
      ) {}

      response = worker.process_signature_help(InteractionWorker::SignatureHelpJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 6))
      assert_equal({ signature_help: nil, syntax_error: true }, response)
    end
  end
end
