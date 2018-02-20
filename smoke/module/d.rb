# If there is a same name module definition, it automatically implements.

# !expects MethodDefinitionMissing: module=::X, method=foo
module X
end
