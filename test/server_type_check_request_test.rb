require_relative "test_helper"

class ServerTypeCheckRequestTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  def dirs
    @dirs ||= []
  end

  def test_request
    Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))
  end

  def test_jobs
    in_tmpdir do
      request = Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))

      request.library_paths << [:lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"]
      request.signature_paths << [:lib, current_dir + "sig/user.rbs"]
      request.code_paths << [:lib, current_dir + "lib/user.rb"]
      request.code_paths << [:lib, current_dir + "lib/account.rb"]
      request.inline_paths << [:lib, current_dir + "lib/inline.rb"]
      request.priority_paths << (current_dir + "lib/account.rb")

      # The priority paths come first, and then the Ruby files, the RBS files, the library files, and the inline files
      assert_equal(
        [
          [:code, :lib, current_dir + "lib/account.rb"],
          [:code, :lib, current_dir + "lib/user.rb"],
          [:signature, :lib, current_dir + "sig/user.rbs"],
          [:library, :lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"],
          [:inline, :lib, current_dir + "lib/inline.rb"]
        ],
        request.jobs
      )

      # The paths checked already are left out
      request.checked(current_dir + "lib/user.rb", Steep::Project::Target.new(name: :lib, options: nil, source_pattern: nil, inline_source_pattern: nil, signature_pattern: nil, code_diagnostics_config: nil, project: nil, unreferenced: false, implicitly_returns_nil: true))
      assert_equal 4, request.jobs.size
      refute_includes request.jobs, [:code, :lib, current_dir + "lib/user.rb"]
    end
  end

  def test_progress
    in_tmpdir do
      target = Steep::Project::Target.new(name: :lib, options: nil, source_pattern: nil, inline_source_pattern: nil, signature_pattern: nil, code_diagnostics_config: nil, project: nil, unreferenced: false, implicitly_returns_nil: true)

      request = Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))
      request.library_paths << [:lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"]
      request.signature_paths << [:lib, current_dir + "sig/user.rbs"]
      request.code_paths << [:lib, current_dir + "lib/user.rb"]
      request.inline_paths << [:lib, current_dir + "lib/inline.rb"]

      assert_equal request.percentage, 0
      assert_equal request.each_target_path.to_set, request.each_unchecked_target_path.to_set

      request.checked(RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs", target)
      assert_equal request.percentage, 25

      request.checked(current_dir + "sig/user.rbs", target)
      assert_equal request.percentage, 50

      request.checked(current_dir + "lib/user.rb", target)
      assert_equal request.percentage, 75

      request.checked(current_dir + "lib/inline.rb", target)
      assert_equal request.percentage, 100

      assert_empty request.each_unchecked_target_path.to_a
    end
  end
end
