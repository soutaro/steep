module Steep
  module Postconditions
    # Applies the return-value establishment postcondition
    # (felixefelip/steep#56) at a `x = <call>` assignment. When `<call>`'s
    # method declares `returns.establishes: [attr, …]`, each attribute is
    # imported as a pure-node fact `x.attr` non-nil on the assigned local
    # — exactly as if `x.attr = <non-nil>` had been written at this call
    # site (reusing the #51 attribute-write narrowing). This carries the
    # "attribute was set" fact across the method-return boundary: `build`
    # establishes it on its returned record, and `x = build` lands it on
    # `x`, so a subsequent `x.save` satisfies its `requires self.attr`
    # precondition even though the write happened in a different method.
    #
    # Extracted from `TypeConstruction` (which is enormous); `.apply` is
    # the sole entry point. Threads the current `TypeConstruction`
    # (`constr`) through and returns the updated one — the helpers are all
    # private and used only by `apply`.
    class ReturnEstablishmentApplier
      def initialize(constr)
        @constr = constr
      end

      def apply(name:, rhs:)
        return @constr if @constr.postconditions.empty?
        return @constr unless rhs.is_a?(::Parser::AST::Node)
        return @constr unless rhs.type == :send || rhs.type == :csend

        call = begin
                 @constr.typing.call_of(node: rhs)
               rescue Typing::UnknownNodeError
                 nil
               end
        return @constr unless call.is_a?(TypeInference::MethodCall::Typed)

        entry = lookup_entry(call, rhs)
        return @constr unless entry&.unconditional

        attrs = entry.unconditional.returns_establishes
        return @constr if attrs.empty?

        receiver_node = ::Parser::AST::Node.new(:lvar, [name])
        attrs.each do |attr|
          @constr = establish_attribute_non_nil(receiver_node, attr)
        end
        @constr
      end

      private

      # Establishes `<receiver_node>.<attr>` as non-nil in the env by
      # caching a pure-call fact for the getter read. Mirrors
      # `TypeConstruction#narrow_attribute_write` (#51) but sources the
      # non-nil type from the getter's own declared return (stripped of
      # `nil`) rather than a written value — there is no written value at
      # the call site, only the postcondition's guarantee that the callee
      # set it.
      def establish_attribute_non_nil(receiver_node, attr)
        read_node = ::Parser::AST::Node.new(:send, [receiver_node, attr])

        getter_call = nil #: TypeInference::MethodCall::Typed?
        non_nil_type = nil #: AST::Types::t?
        begin
          # Type the read in a throwaway child typing to obtain a real getter
          # `MethodCall` (and confirm it is a pure attr reader). The child is
          # discarded, so the synthetic read leaks no diagnostics/typings.
          @constr.typing.new_child do |child|
            pair = @constr.with_new_typing(child).synthesize(read_node, hint: nil)
            call = pair.constr.typing.call_of(node: read_node)
            if call.is_a?(TypeInference::MethodCall::Typed) &&
                pair.constr.typing.errors.empty? &&
                @constr.pure_send?(call, receiver_node, [])
              getter_call = call
              ret = call.return_type
              non_nil_type = @constr.checker.factory.unwrap_optional(ret) || ret
            end
          end
        rescue StandardError => exn
          Steep.logger.warn { "[postconditions] return-value establishment failed for .#{attr}: #{exn.message}" }
          return @constr
        end
        return @constr unless getter_call && non_nil_type

        @constr.update_type_env do |env|
          env.add_pure_call(read_node, getter_call, non_nil_type)
        end
      end

      # Looks up the `unconditional` postcondition entry for a `x = <call>`
      # site, trying two keyings of the same method:
      #
      #   1. the RECEIVER's static type — the class the postcondition is
      #      keyed on when the method BODY was defined (and inferred) there.
      #      This is what matches an inherited/reopened method: the AR
      #      pseudo-code defines `build` on `Post_Assignment::…Proxy`, but
      #      the RBS declares it on the parent `Assignment::…Proxy`, so the
      #      call's method-decl points at the parent while the entry lives
      #      under the subclass the receiver actually is.
      #   2. the method DECLS' defining types — covers the plain case where
      #      the entry is keyed on the class that declares the method
      #      (including singleton `def self.build`).
      #
      # First hit wins; the establishment is receiver-agnostic either way.
      def lookup_entry(call, rhs)
        if (recv_name = receiver_type_name(rhs))
          entry = @constr.postconditions.lookup_instance(recv_name.to_s, call.method_name)
          return entry if entry
        end

        call.method_decls.each do |decl|
          name = decl.method_name
          type_name =
            case name
            when InstanceMethodName, SingletonMethodName
              name.type_name
            end
          next unless type_name
          entry = @constr.postconditions.lookup_instance(type_name.to_s, name.method_name)
          return entry if entry
        end
        nil
      end

      # Resolves the receiver type-name of a `x = <send>` for postcondition
      # lookup. An explicit receiver uses its typed-out type; an implicit
      # self receiver (`x = build`) uses the enclosing self type. Only
      # class/module instance and singleton names are usable as keys.
      def receiver_type_name(rhs)
        recv = rhs.children[0]
        type =
          if recv
            @constr.typing.type_of(node: recv) rescue nil
          else
            @constr.self_type
          end
        type = @constr.self_type if type.is_a?(AST::Types::Self)
        case type
        when AST::Types::Name::Instance, AST::Types::Name::Singleton
          type.name
        end
      end
    end
  end
end
