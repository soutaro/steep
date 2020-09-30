require_relative "test_helper"

class LSPUtilsTest < Minitest::Test
  include TestHelper
  include ShellHelper

  class Test
    include Steep::Server::Utils
  end

  def test_update_full
    assert_equal "HELLO world", Test.new.apply_change({ text: "HELLO world" }, "hello world")
  end

  def test_update_partial
    assert_equal "HELLO world",
                 Test.new.apply_change(
                   {
                     text: "HELLO",
                     range: {
                       start: { line: 0, character: 0 },
                       end: { line: 0, character: 5 }
                     }
                   },
                   "hello world"
                 )
  end
end
