module Steep
  module Drivers
    class Vendor
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :stdin

      attr_accessor :vendor_dir
      attr_accessor :clean_before

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin

        @clean_before = false
        @vendor_dir = nil
      end

      def run
        stdout.puts "Vendoring into #{vendor_dir}..."

        vendorer = Ruby::Signature::Vendorer.new(vendor_dir: vendor_dir)

        if clean_before
          stdout.puts "  Cleaning directory..."
          vendorer.clean!
        end

        stdout.puts "  Vendoring standard libraries..."
        vendorer.stdlib!

        if defined?(Bundler)
          Bundler.locked_gems.specs.each do |spec|
            if Ruby::Signature::EnvironmentLoader.gem_sig_path(spec.name, spec.version.to_s).directory?
              stdout.puts "  Vendoring rubygem: #{spec.full_name}..."
              vendorer.gem! spec.name, spec.version.to_s
            end
          end
        end

        0
      end
    end
  end
end
