# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_signatures_setter
    config = Steep::Configuration.new
    config.signatures = ["sig-private"]
    expected_signatures = [Pathname("sig"), Pathname("sig-private")]

    assert_equal expected_signatures, config.signatures
  end

  def test_with_merged_options
    steepfile_contents = <<~STEEPFILE
      signatures "sig-private"
    STEEPFILE

    expected_signatures = [Pathname("sig"), Pathname("sig-private"), Pathname("sig-third")]

    File.stub(:read, steepfile_contents) do
      File.stub(:exists?, true) do
        Steep::Configuration.with_merged_options(%w[-I sig-third]) do |config|
          assert_equal expected_signatures, config.signatures
        end
      end
    end
  end
end
