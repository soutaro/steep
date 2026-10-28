# The generic fallback of `+` takes a `_Coerce[Int, O, S]` and returns `R` with `O < _Add[S, R]`.
# `Rat <: _Add[S, R]` is checked once `S` is solved from `Rat#coerce`: with `S = Rat`, only `(Rat) -> Rat`
# of `Rat#+` is reached, so that `R = Rat`. Picking the first overload `(Int) -> Rat` would bound `S` by `Int`.
i = Int.new
r = Rat.new
f = Flt.new

# @type var x: Rat
x = i + r

# @type var y: Flt
y = i + f

# @type var z: Rat
z = r + i

# @type var w: Flt
w = r + f

# `Num` has no `coerce`: no overload accepts it
i + Num.new
