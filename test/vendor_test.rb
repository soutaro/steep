require_relative "test_helper"

class VendorTest < Minitest::Test
  include TestHelper
  include ShellHelper

  Vendor = Steep::Drivers::Vendor

  def stdout
    @stdout ||= StringIO.new
  end

  def stderr
    @stderr ||= StringIO.new
  end

  def stdin
    @stdin ||= StringIO.new
  end

  def dirs
    @dirs ||= []
  end

  def test_vendor
    in_tmpdir do
      path = current_dir + "vendor/sigs"

      v = Vendor.new(stdout: stdout, stdin: stdin, stderr: stderr)
      v.vendor_dir = path
      v.clean_before = true

      v.run

      assert_match(/Vendoring into #{path}.../, stdout.string)
      assert_operator path, :directory?
      assert_operator path + "stdlib", :directory?
      assert_operator path + "gems/with_steep_types", :directory?
    end
  end
end
