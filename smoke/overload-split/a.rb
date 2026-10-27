calc = Calc.new

# @type var y: Integer | Float
y = (_ = nil)

# The members of the union are matched one by one: `Integer | Float`
a = calc.plus(y)
a.is_a?(Integer) || a.is_a?(Float)

# @type var x: Integer | String
# @type var w: Integer | String
x = (_ = nil)
w = (_ = nil)

# Every combination of the members has an overload: `:ii | :is | :si | :ss`
calc.pair(x, w)

# A member without an overload fails the whole call: `Float` has none
calc.pair(x, y)

# A keyword argument is split the same way
calc.scale(by: y)

# The type parameter is solved per member: `String | Array[String] | nil`
# @type var store: Store[String]
# @type var i: Integer | Range[Integer]
store = (_ = nil)
i = (_ = nil)
store.get(i)

# No overload accepts `Symbol`: the call fails as it did
# @type var z: Integer | Symbol
z = (_ = nil)
calc.plus(z)

# The core library: `Integer#+` with `Integer | Float` is `Integer | Float`
n = 1 + y
n.is_a?(Integer) || n.is_a?(Float)
