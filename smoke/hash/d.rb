# @type var params: { name: String, id: Integer }

params = { id: 30, name: "Matz" }

# !expects IncompatibleAssignment: lhs_type={ :name => ::String, :id => ::Integer }, rhs_type=::Hash<::Symbol, ::String>
params = { id: "30", name: "foo", email: "matsumoto@soutaro.com" }
