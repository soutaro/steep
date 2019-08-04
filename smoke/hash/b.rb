# @type var x: Hash[Symbol, String?]

x = { foo: "foo" }
x = { foo: nil }

# !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, (::String | nil)], rhs_type=::Hash[::Symbol, ::Integer]
x = { foo: 3 }
