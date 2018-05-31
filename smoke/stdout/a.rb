class A
  def write_to(io:)
    io.puts "Hello World"
  end
end

A.new(STDOUT)
A.new(StringIO.new)
