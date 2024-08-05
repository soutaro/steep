class MemGraph
  attr_reader :edges

  attr_reader :checked

  attr_reader :generation

  def initialize(generation)
    @generation = generation
    @edges = []
    @checked = Set.new.compare_by_identity
    @checked << self
    @checked << edges
    @checked << checked
  end

  IVARS = Object.instance_method(:instance_variables)
  IVGET = Object.instance_method(:instance_variable_get)

  def traverse(object)
    return if checked.include?(object)
    checked << object

    case object
    when Array
      object.each do |value|
        insert_edge(object, value)
        traverse(value)
      end
    when Hash
      object.each do |key, value|
        insert_edge(object, key)
        insert_edge(object, value)

        traverse(key)
        traverse(value)
      end
    else
      IVARS.bind_call(object).each do |name|
        if name.is_a?(Symbol)
          value = IVGET.bind_call(object, name)
          traverse(value)
          insert_edge(object, value)
        else
          STDERR.puts "Unexpected instance variable name: #{name} in #{object.class}"
        end
      end
    end
  end

  def insert_edge(source, dest)
    case dest
    when Integer, Symbol, nil, true, false, Float
    else
      edges << [
        "#{source.class}(#{source.__id__})",
        "#{dest.class}(#{dest.__id__})",
      ]
    end
  end

  def dot
    "digraph G {\n" + edges.uniq.map do |source, dest|
      "  #{source} -> #{dest};"
    end.join("\n") + "}"
  end
end
