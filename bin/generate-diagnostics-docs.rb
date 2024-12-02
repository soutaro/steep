# rbs_inline: enabled

require "rbs"
require "steep"

class RubyDiagnosticsVisitor < RBS::AST::Visitor
  attr_reader :classes #: Hash[String, String]
  attr_reader :templates #: Hash[Symbol, String]

  def initialize #: void
    @classes = {}
    @templates = {}
  end

  # @rbs ...
  def visit_declaration_class(node)
    unless node.annotations.find { _1.string == "diagnostics--skip" }
      if node.comment
        name = node.name.to_s
        classes[name] = node.comment.string
      end
    end

    super
  end

  # @rbs ...
  def visit_member_method_definition(node)
    if node.annotations.find { _1.string == "diagnostics--template" }
      if node.comment
        templates[node.name] = node.comment.string
      end
    end
  end

  # @rbs (IO) -> void
  def format_templates(io)
    io.puts "## Configuration Templates"

    io.puts <<~MD
      Steep provides several templates to configure diagnostics for Ruby code.
      You can use these templates or customize them to suit your needs via `#configure_code_diagnostics` method in `Steepfile`.

      The following templates are available:

    MD

    io.puts "<dl>"
    templates.keys.sort.each do |key|
      body = templates.fetch(key)

      io.puts "<dt><code>Ruby.#{key}</code></dt>"
      io.puts "<dd>#{body}</dd>"
    end
    io.puts "</dl>"
    io.puts
  end

  # @rbs (IO) -> void
  def format_class(io)
    classes.keys.sort.each do |key|
      content = classes[key]

      # io.puts "<h2 id='Ruby::#{key}'>Ruby::#{key}</h2>"
      io.puts "<a name='Ruby::#{key}'></a>"
      io.puts "## Ruby::#{key}"
      io.puts
      io.puts content
      io.puts

      configs = templates.keys

      io.puts "### Severity"
      io.puts
      io.puts "| #{configs.map { "#{_1}" }.join(" | ")} |"
      io.puts "| #{configs.map{"-"}.join(" | ")} |"

      line = configs.map {|config|
        hash = Steep::Diagnostic::Ruby.__send__(config) #: Hash[Class, untyped]
        const =Steep::Diagnostic::Ruby.const_get(key.to_sym)
        "#{hash[const] || "-"}"
      }
      io.puts "| #{line.join(" | ")} |"
      io.puts
    end
  end

  # @rbs (Pathname) { (instance) -> void } -> void
  def self.visit_file(path, &block)
    STDERR.puts "Reading #{path}..."
    buffer = RBS::Buffer.new(name: path, content: path.read)
    _, _dirs, decls = RBS::Parser.parse_signature(buffer)

    visitor = new()
    visitor.visit_all(decls)

    yield visitor
  end
end

diagnostic_dir = Pathname(__dir__ || raise) + "../sig/steep/diagnostic"
output_dir = Pathname(__dir__ || raise) + "../manual"

RubyDiagnosticsVisitor.visit_file(diagnostic_dir + "ruby.rbs") do |visitor|
  STDERR.puts ">> Writing #{output_dir + "ruby-diagnostics.md"}..."
  (output_dir + "ruby-diagnostics.md").open("w") do |io|
    io.puts "# Ruby Code Diagnostics"
    io.puts
    visitor.format_templates(io)
    visitor.format_class(io)
  end
end
