require_relative "test_helper"

class LangserverTest < Minitest::Test
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def langserver_command(steepfile=nil)
    "#{RUBY_PATH} #{__dir__}/../exe/steep langserver --log-level=error".tap do |s|
      if steepfile
        s << " --steepfile=#{steepfile}"
      end
    end
  end

  def test_run
    in_tmpdir do
      (current_dir + "lib").mkdir
      (current_dir + "sig").mkdir
      (current_dir + "Steepfile").write <<EOF
D = Steep::Diagnostic

target :app do
  check "lib"
  signature "sig"

  configure_code_diagnostics(D::Ruby.all_error)
end
EOF

      (current_dir + "lib/hello.rb").write <<Ruby
class Hello
  attr_reader :name
end
Ruby
      (current_dir + "sig/hello.rbs").write <<RBS
class Hello
  attr_reader name: String
end
RBS

      Open3.popen2(langserver_command(current_dir + "Steepfile")) do |stdin, stdout|
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)
        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)

        lsp = LSPDouble.new(reader: reader, writer: writer)

        lsp.start do
          lsp.open_file(current_dir + "lib/hello.rb")
          
          finally_holds do
            lsp.synchronize_ui do
              assert_equal [], lsp.diagnostics["#{file_scheme}#{current_dir}/lib/hello.rb"]
              assert_equal [], lsp.diagnostics["#{file_scheme}#{current_dir}/sig/hello.rbs"]
            end
          end

          lsp.edit_file(current_dir + "lib/hello.rb", content: <<RUBY, version: 1)
class Hello
  attr_reader :other_name

end
RUBY
          lsp.save_file(current_dir + "lib/hello.rb")

          finally_holds do
            lsp.synchronize_ui do
              assert_equal 1, lsp.diagnostics["#{file_scheme}#{current_dir}/lib/hello.rb"].size
              assert_equal [], lsp.diagnostics["#{file_scheme}#{current_dir}/sig/hello.rbs"]
            end
          end

          items = lsp.complete_on(path: current_dir + "lib/hello.rb", line: 2, character: 0)
          refute_empty items
        end

        lsp.reader_thread.join
      end
    end
  end
end
