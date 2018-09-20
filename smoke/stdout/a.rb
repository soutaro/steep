class A
  def write_to(io:)
    io.puts "Hello World"
  end
end

A.new.write_to(io: STDOUT)
A.new.write_to(io: StringIO.new)
