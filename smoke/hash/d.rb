# @type var params: { name: String, id: Integer }

params = { id: 30, name: "Matz" }

# !expects IncompatibleAssignment: lhs_type={ :id => ::Integer, :name => ::String }, rhs_type={ :email => ::String, :id => ::String, :name => ::String }
params = { id: "30", name: "foo", email: "matsumoto@soutaro.com" }
