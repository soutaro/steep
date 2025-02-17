module Steep
  module Server
    module CustomMethods
      module FileLoad
        METHOD = "$/steep/file/load"

        def self.notification(params)
          { method: METHOD, params: params }
        end
      end

      module FileReset
        METHOD = "$/steep/file/reset"

        def self.notification(params)
          { method: METHOD, params: params }
        end
      end

      module TypeCheck
        METHOD = "$/steep/typecheck"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module TypeCheckGroups
        METHOD = "$/steep/typecheck/groups"

        def self.notification(params)
          { method: METHOD, params: params }
        end
      end

      module TypeCheck__Start
        METHOD = "$/steep/typecheck/start"

        def self.notification(params)
          { method: METHOD, params: params }
        end
      end

      module TypeCheck__Progress
        METHOD = "$/steep/typecheck/progress"

        def self.notification(params)
          { method: METHOD, params: params }
        end
      end

      module Stats
        METHOD = "$/steep/stats"

        def self.request(id)
          { method: METHOD, id: id, params: nil }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module Groups
        METHOD = "$/steep/groups"

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module Refork
        METHOD = "$/steep/refork"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end
    end
  end
end
