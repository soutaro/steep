module Steep
  module Drivers
    class Init
      attr_reader :stdout
      attr_reader :stderr
      attr_accessor :force_write

      include Utils::DriverHelper

      TEMPLATE = <<~EOF
      # target :lib do
      #   signature "sig"
      # 
      #   check "lib"                       # Directory name
      #   check "Gemfile"                   # File name
      #   check "app/models/**/*.rb"        # Glob
      #   # ignore "lib/templates/*.rb"        
      #   
      #   # library "pathname", "set"       # Standard libraries
      #   # library "strong_json"           # Gems
      # end

      # target :spec do
      #   signature "sig", "sig-private"
      # 
      #   check "spec"
      # 
      #   # library "pathname", "set"       # Standard libraries
      #   # library "rspec"
      # end
      EOF

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @force_write = false
      end

      def run
        path = steepfile || Pathname("Steepfile")

        if path.file? && !force_write
          stdout.puts "#{path} already exists, --force to overwrite"
          return 1
        end

        stdout.puts "Writing #{path}..."
        path.write(TEMPLATE)

        0
      end
    end
  end
end
