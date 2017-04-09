namespace steep

    interface Method
    end

    interface Type
    end

    interface Block
    end

    namespace type
        interface Type.Interface
          def initialize: (
        end
    end

    interface SomeInterface
      def method: (Integer, ?String, *any, foo: Symbol, bar: ?Array<any>, **baz) ?{ String -> any } -> any
    end
end
