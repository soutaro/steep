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

      request.library_paths << (RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs")
      request.signature_paths << (current_dir + "sig/user.rbs")
      request.code_paths << (current_dir + "lib/user.rb")

      json = request.as_json(assignment: Services::PathAssignment.all)

      assert_equal(
        {
          guid: "guid",
          library_uris: ["#{file_scheme}#{RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"}"],
          signature_uris: ["#{file_scheme}#{current_dir + "sig/user.rbs"}"],
          code_uris: ["#{file_scheme}#{current_dir + "lib/user.rb"}"],
          priority_uris: []
        },
        json
      )
    end
  end

  def test_as_json_none
    in_tmpdir do
      request = Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))

      request.library_paths << (RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs")
      request.signature_paths << (current_dir + "sig/user.rbs")
      request.code_paths << (current_dir + "lib/user.rb")

      json = request.as_json(assignment: Services::PathAssignment.new(max_index: 1, index: 1))

      assert_equal(
        {
          guid: "guid",
          library_uris: [],
          signature_uris: [],
          code_uris: [],
          priority_uris: []
        },
        json
      )
    end
  end

  def test_progress
    in_tmpdir do
      request = Server::TypeCheckController::Request.new(guid: "guid", progress: Server::WorkDoneProgress.new("guid"))
      request.library_paths << (RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs")
      request.signature_paths << (current_dir + "sig/user.rbs")
      request.code_paths << (current_dir + "lib/user.rb")

      assert_equal request.percentage, 0
      assert_equal request.all_paths, request.unchecked_paths

      request.checked(RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs")
      assert_equal request.percentage, 33

      request.checked(current_dir + "sig/user.rbs")
      assert_equal request.percentage, 66

      request.checked(current_dir + "lib/user.rb")
      assert_equal request.percentage, 100

      assert_equal Set[], request.unchecked_paths
    end
  end
end
