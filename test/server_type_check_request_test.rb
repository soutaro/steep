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

  def test_as_json_all
    in_tmpdir do
      request = Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))

      request.library_paths << [:lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"]
      request.signature_paths << [:lib, current_dir + "sig/user.rbs"]
      request.code_paths << [:lib, current_dir + "lib/user.rb"]
      request.inline_paths << [:lib, current_dir + "lib/inline.rb"]

      json = request.as_json(assignment: Services::PathAssignment.all)

      assert_equal(
        {
          guid: "guid",
          library_uris: [["lib", "#{file_scheme}#{RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"}"]],
          signature_uris: [["lib", "#{file_scheme}#{current_dir + "sig/user.rbs"}"]],
          code_uris: [["lib", "#{file_scheme}#{current_dir + "lib/user.rb"}"]],
          inline_uris: [["lib", "#{file_scheme}#{current_dir + "lib/inline.rb"}"]],
          priority_uris: []
        },
        json
      )
    end
  end

  def test_as_json_none
    in_tmpdir do
      request = Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))

      request.library_paths << [:lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"]
      request.signature_paths << [:lib, current_dir + "sig/user.rbs"]
      request.code_paths << [:lib, current_dir + "lib/user.rb"]
      request.inline_paths << [:lib, current_dir + "lib/inline.rb"]

      json = request.as_json(assignment: Services::PathAssignment.new(max_index: 1, index: 1))

      assert_equal(
        {
          guid: "guid",
          library_uris: [],
          signature_uris: [],
          code_uris: [],
          inline_uris: [],
          priority_uris: []
        },
        json
      )
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
