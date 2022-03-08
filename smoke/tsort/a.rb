require "tsort"

# @type var g: Hash[Integer, Array[Integer]]
g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}

# @type var each_node: ^() { (Integer) -> void } -> void
each_node = -> (&b) { g.each_key(&b) }
# @type var each_child: ^(Integer) { (Integer) -> void } -> void
each_child = -> (n, &b) { g[n].each(&b) }

# @type var xs: Array[Integer]
xs = TSort.tsort(each_node, each_child)
