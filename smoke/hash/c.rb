# @type var params: t
params = _ = nil

id = params[:id]
id.abcdefg

name = params[:name]
name.abcdefg

params[(_=nil) ? :id : :name].abcdefg

# @type var controller: Controller
controller = _ = nil

controller.params[:id] + 3
