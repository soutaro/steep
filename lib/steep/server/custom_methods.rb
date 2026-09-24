module Steep
  module Server
    module CustomMethods
      module FileLoad
        METHOD = "$/steep/file/load"

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

      module TypeCheck__File
        METHOD = "$/steep/typecheck/file"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
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

      module Query__Definition
        METHOD = "$/steep/query/definition"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module Hover
        METHOD = "$/steep/hover"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module Completion
        METHOD = "$/steep/completion"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module SignatureHelp
        METHOD = "$/steep/signatureHelp"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module Source__Symbol
        METHOD = "$/steep/source/symbol"

        def self.request(id, params)
          { method: METHOD, id: id, params: params }
        end

        def self.response(id, result)
          { id: id, result: result }
        end
      end

      module Query__Diagnostics
        METHOD = "$/steep/query/diagnostics"

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
