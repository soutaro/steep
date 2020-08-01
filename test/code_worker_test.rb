require "test_helper"

class CodeWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol::Interface

  def dirs
    @dirs ||= []
  end

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

  def shutdown!
    master_writer.write(
      method: :shutdown,
      params: nil
    )

    master_writer.write(
      method: :exit
    )
  end

  def test_worker_shutdown
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      run_worker(Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)) do |worker|
        master_writer.write(
          method: :shutdown,
          params: nil
        )

        master_writer.write(
          method: :exit
        )
      end
    end
  end

  def test_target_files
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      assert_empty worker.target_files.keys

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/test/hello_test.rb"
            ]
          ).to_hash
        }
      )

      assert_operator worker.target_files, :key?, Pathname("lib/hello.rb")
      assert_operator worker.target_files, :key?, Pathname("test/hello_test.rb")
    end
  end

  def test_update_target_source
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      lib_target = project.targets[0]

      worker = Server::CodeWorker.new(project: project,
                                      reader: worker_reader,
                                      writer: worker_writer,
                                      queue: [])
      worker.queue_delay = 0

      assert_empty worker.target_files.keys

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/test/hello_test.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Foo
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      assert_equal <<-RUBY, lib_target.source_files[Pathname("lib/hello.rb")].content
class Foo
end
      RUBY

      assert_equal 1, worker.target_files[Pathname("lib/hello.rb")]

      assert_equal [[Pathname("lib/hello.rb"), 1, lib_target]],
                   worker.queue
    end
  end

  def test_update_nontarget_source
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      lib_target = project.targets[0]

      worker = Server::CodeWorker.new(project: project,
                                      reader: worker_reader,
                                      writer: worker_writer,
                                      queue: [])

      assert_empty worker.target_files.keys

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/test/hello_test.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/world.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class World
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      assert_equal <<-RUBY, lib_target.source_files[Pathname("lib/world.rb")].content
class World
end
      RUBY

      refute_operator worker.target_files, :key?, Pathname("lib/world.rb")

      assert_empty worker.queue
    end
  end

  def test_update_signature
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      lib_target = project.targets[0]

      worker = Server::CodeWorker.new(project: project,
                                      reader: worker_reader,
                                      writer: worker_writer,
                                      queue: [])
      worker.queue_delay = 0

      assert_empty worker.target_files.keys

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Hello
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      worker.queue.clear

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/sig/hello.rbs"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Hello
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      assert_equal [
                     [Pathname("lib/hello.rb"), 1, lib_target]
                   ],
                   worker.queue
    end
  end

  def test_typecheck_success
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :lenient
end
EOF

      target = project.targets[0]
      target.add_source Pathname("lib/success.rb"), <<RUBY
class Hello
  1 + ""
  1.hello_world
end
RUBY

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      Thread.start do
        worker.typecheck_file Pathname("lib/success.rb"), project.targets[0]
      end

      master_reader.read do |response|
        uri = response[:params][:uri]
        diagnostics = response[:params][:diagnostics]

        assert_equal Pathname("lib/success.rb"), project.relative_path(Pathname(URI.parse(uri).path))

        assert_equal [
                       {
                         range: {
                           start: { line: 1, character: 2 },
                           end: { line: 1, character: 8 }
                         },
                         severity: 1,
                         message: "UnresolvedOverloading: receiver=::Integer, method_name=+, method_types=(::Integer) -> ::Integer | (::Float) -> ::Float | (::Rational) -> ::Rational | (::Complex) -> ::Complex (1 + \"\")"
                       }
                     ],
                     diagnostics
        break
      end
    end
  end

  def test_typecheck_annotation_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      target = project.targets[0]
      target.add_source Pathname("lib/annotation_syntax_error.rb"), <<RUBY
# @type var foo: []]
foo = 30
RUBY
      target.add_source Pathname("lib/ruby_syntax_error.rb"), <<RUBY
class Hello
RUBY

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      Thread.start do
        worker.typecheck_file Pathname("lib/annotation_syntax_error.rb"), project.targets[0]
      end

      master_reader.read do |response|
        uri = response[:params][:uri]
        diagnostics = response[:params][:diagnostics]

        assert_equal Pathname("lib/annotation_syntax_error.rb"), project.relative_path(Pathname(URI.parse(uri).path))

        assert_equal({
                       start: { line: 0, character: 1 },
                       end: { line: 0, character: 20 }
                     },
                     diagnostics[0][:range])

        assert_match /Annotation syntax error: parse error on value/,
                     diagnostics[0][:message]
        break
      end
    end
  end

  def test_typecheck_ruby_syntax_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      target = project.targets[0]
      target.add_source Pathname("lib/ruby_syntax_error.rb"), <<RUBY
class Hello
RUBY

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.typecheck_file Pathname("lib/ruby_syntax_error.rb"), project.targets[0]
      master_reader.read do |response|
        uri = response[:params][:uri]
        diagnostics = response[:params][:diagnostics]

        assert_equal Pathname("lib/ruby_syntax_error.rb"), project.relative_path(Pathname(URI.parse(uri).path))

        assert_equal [],
                     diagnostics
        break
      end
    end
  end

  def test_run
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      requests = []
      t = Thread.new do
        master_reader.read do |request|
          requests << request
        end
      end

      run_worker(Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)) do |worker|
        master_writer.write(
          {
            method: "workspace/executeCommand",
            params: LSP::ExecuteCommandParams.new(
              command: "steep/registerSourceToWorker",
              arguments: [
                "file://#{current_dir}/lib/hello.rb",
                "file://#{current_dir}/test/hello_test.rb"
              ]
            )
          }
        )

        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/lib/hello.rb"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class Foo
end
                RUBY
                )
              ]
            )
          }
        )

        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/lib/world.rb"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class World
end
                RUBY
                )
              ]
            )
          }
        )

        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/sig/lib.rbs"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class Hello
end
                RUBY
                )
              ]
            )
          }
        )

        shutdown!
      end

      t.join

      assert requests.all? {|req|
        req[:method] == "textDocument/publishDiagnostics" &&
          req[:params][:uri].end_with?("lib/hello.rb") &&
          req[:params][:diagnostics] == []
      }
    end
  end
end
