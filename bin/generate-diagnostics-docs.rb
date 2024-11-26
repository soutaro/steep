# rbs_inline: enabled

require "rbs"

class Visitor < RBS::AST::Visitor
  attr_reader :output #: Hash[String, String]

  def initialize #: void
    @output = {}
  end

  # @rbs ...
  def visit_declaration_class(node)
    if node.annotations.find { _1.string == "diagnostic-class" }
      if node.comment
        name = node.name.to_s
        @output[name] = node.comment.string
      end
    end
  end

  # @rbs (IO) -> void
  def format(io)
    output.keys.sort.each do |key|
      content = output[key]

      io.puts "## Ruby::#{key}"
      io.puts
      io.puts content
      io.puts
    end
  end

  # @rbs (Pathname) { (instance) -> void } -> void
  def self.visit_file(path, &block)
    STDERR.puts "Reading #{path}..."
    buffer = RBS::Buffer.new(name: path, content: path.read)
    _, _dirs, decls = RBS::Parser.parse_signature(buffer)

    visitor = Visitor.new()
    visitor.visit_all(decls)

    yield visitor
  end
end

diagnostic_dir = Pathname(__dir__ || raise) + "../sig/steep/diagnostic"
output_dir = Pathname(__dir__ || raise) + "../guides/src/diagnostics"

Visitor.visit_file(diagnostic_dir + "ruby.rbs") do |visitor|
  STDERR.puts ">> Writing #{output_dir + "ruby.md"}..."
  (output_dir + "ruby.md").open("w") do |io|
    io.puts "# Ruby Code Diagnostics"
    io.puts
    visitor.format(io)
  end
end
