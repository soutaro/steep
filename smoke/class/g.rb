# !expects MethodDefinitionMissing: module=::B, method=name
class B
end

# !expects MethodDefinitionMissing: module=::B, method=name
class C
  # @implements ::B
end
