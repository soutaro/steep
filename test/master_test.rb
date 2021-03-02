require "test_helper"

class MasterTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  def dirs
    @dirs ||= []
  end

  def test_code_type_check
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 1)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
class Foo
end
        RUBY

        ui.open_file(project.absolute_path(Pathname("lib/bar.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/bar.rb")), content: <<-RUBY, version: 0)
class Bar
end
        RUBY

        finally_holds do
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("lib/bar.rb")))
        end
      end

      main_thread.join
    end
  end

  def test_signature_type_check
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :strict
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 1)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
class Foo
end
        RUBY

        finally_holds do
          assert_equal [],
                       ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
        end

        ui.open_file(project.absolute_path(Pathname("sig/foo.rbs")))
        ui.edit_file(project.absolute_path(Pathname("sig/foo.rbs")), content: <<-RBS, version: 0)
class Foo
  def foo: () -> void
end
        RBS


        finally_holds do
          assert_equal 1, ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb"))).size
        end

        finally_holds timeout: 30 do
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("sig/foo.rbs")))
        end
      end

      main_thread.join
    end
  end

  def test_code_interaction
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :strict
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 2)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
x = 100
x.ab
        RUBY

        hover = ui.hover_on(path: project.absolute_path(Pathname("lib/foo.rb")), line: 1, character: 0)

        assert_equal({ kind: "markdown", value: "`x`: `::Integer`" }, hover[:contents])
        assert_equal({ line: 1, character: 0 }, hover[:range][:start])
        assert_equal({ line: 1, character: 1 }, hover[:range][:end])

        completion = ui.complete_on(path: project.absolute_path(Pathname("lib/foo.rb")), line: 1, character: 4)

        assert_instance_of Array, completion[:items]
      end

      main_thread.join
    end
  end
end
