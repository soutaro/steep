# @type var params: t
params = _ = nil

id = params[:id]
# !expects NoMethodError: type=::Integer, method=abcdefg
id.abcdefg

name = params[:name]
# !expects NoMethodError: type=::String, method=abcdefg
name.abcdefg

# !expects NoMethodError: type=(::Integer | ::String), method=abcdefg
params[(_=nil) ? :id : :name].abcdefg

# @type var controller: Controller
controller = _ = nil

controller.params[:id] + 3
