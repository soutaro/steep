# !expects UnexpectedDynamicMethod: module=::B, method=type
class B
  # @implements B

  # @dynamic name
  attr_reader :name

  # @dynamic type
  attr_reader :type
end
