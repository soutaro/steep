# @type var e: _E
# @type var d: D

e = (_ = nil)
d = (_ = nil)

e = d

# !expects IncompatibleAssignment: lhs_type=::D, rhs_type=::_E
d = e
