require_relative "test_helper"

# Unit tests for the source-walking part of the delegation chain
# narrowing pipeline (felixefelip/steep#32). The analyzer only
# recognizes shapes; semantic application happens in
# `TypeConstruction` and is covered by integration tests.
class DelegationAnalyzerTest < Minitest::Test
  DelegationAnalyzer = Steep::TypeInference::DelegationAnalyzer

  def parse(source)
    parser = Steep::Source.new_parser
    buffer = ::Parser::Source::Buffer.new("<test>")
    buffer.source = source
    parser.parse(buffer)
  end

  def analyze(source)
    DelegationAnalyzer.analyze(parse(source))
  end

  def test_detects_manual_same_name_delegation_via_attr_send
    # `def x; receiver.x; end` where `receiver` is an implicit-self
    # send (likely an attr_reader) — the most common manual delegation
    # pattern in Ruby code.
    result = analyze(<<~RUBY)
      class Ticket
        def venue_name
          event.venue_name
        end
      end
    RUBY

    info = result.dig("Ticket", :venue_name)
    refute_nil info, "expected delegation info for Ticket#venue_name"
    assert_equal :attr_send, info.receiver_kind
    assert_equal :event, info.receiver_name
    assert_equal :venue_name, info.delegate_method
  end

  def test_detects_renaming_forward
    # `def venue_name; venue.name; end` — outer name differs from
    # the inner send's name. Still narrowing-compatible: typing
    # `host.venue_name` is equivalent to typing `host.venue.name`,
    # so a narrowing on `host.venue` in the caller env propagates.
    result = analyze(<<~RUBY)
      class Event
        def venue_name
          venue.name
        end
      end
    RUBY

    info = result.dig("Event", :venue_name)
    refute_nil info, "expected delegation info for renaming forward"
    assert_equal :attr_send, info.receiver_kind
    assert_equal :venue, info.receiver_name
    assert_equal :name, info.delegate_method
  end

  def test_detects_manual_same_name_delegation_via_ivar
    # `def x; @receiver.x; end` — receiver is the ivar directly.
    result = analyze(<<~RUBY)
      class Ticket
        def venue_name
          @event.venue_name
        end
      end
    RUBY

    info = result.dig("Ticket", :venue_name)
    refute_nil info
    assert_equal :ivar, info.receiver_kind
    assert_equal :"@event", info.receiver_name
    assert_equal :venue_name, info.delegate_method
  end

  def test_skips_methods_with_transforming_body
    # `def x; receiver.x.to_s; end` — body has a transformation on the
    # delegated call. The narrowing assumption ("calls to `host.x`
    # are semantically `host.receiver.x`") doesn't hold; skip.
    result = analyze(<<~RUBY)
      class Ticket
        def venue_name
          event.venue_name.to_s
        end
      end
    RUBY

    assert_nil result.dig("Ticket", :venue_name)
  end

  def test_skips_methods_with_multi_statement_body
    result = analyze(<<~RUBY)
      class Ticket
        def venue_name
          do_something
          event.venue_name
        end
      end
    RUBY

    assert_nil result.dig("Ticket", :venue_name)
  end

  def test_detects_renaming_wrapper_as_forward
    # Different name (`display_name → event.title`) — still
    # narrowing-compatible. Captured as a forward with
    # `delegate_method: :title`.
    result = analyze(<<~RUBY)
      class Ticket
        def display_name
          event.title
        end
      end
    RUBY

    info = result.dig("Ticket", :display_name)
    refute_nil info
    assert_equal :title, info.delegate_method
    assert_equal :event, info.receiver_name
  end

  def test_handles_nested_modules_correctly
    # The class name in the registry is the full nesting path.
    result = analyze(<<~RUBY)
      module Concerts
        class Ticket
          def venue_name
            event.venue_name
          end
        end
      end
    RUBY

    info = result.dig("Concerts::Ticket", :venue_name)
    refute_nil info
    assert_equal :attr_send, info.receiver_kind
    assert_equal :event, info.receiver_name
    assert_equal :venue_name, info.delegate_method
  end

  def test_skips_singleton_def_self_methods
    # Delegation analysis is instance-only; singleton patterns are
    # rarely true forwards and the narrowing model doesn't apply.
    result = analyze(<<~RUBY)
      class Ticket
        def self.venue_name
          event.venue_name
        end
      end
    RUBY

    assert_nil result.dig("Ticket", :venue_name)
  end

  def test_top_level_defs_are_ignored
    # No enclosing class — nothing to attach delegation info to.
    result = analyze(<<~RUBY)
      def venue_name
        event.venue_name
      end
    RUBY

    assert_empty result
  end

  def test_accepts_arg_forwarding_delegation
    # `def x(*a, **kw); receiver.x(*a, **kw); end` — common shape for
    # wrapper methods that pass everything through. We accept it; the
    # actual arg compatibility check is left to Steep's method-call
    # type checker at apply time.
    result = analyze(<<~RUBY)
      class Wrapper
        def perform(*args, **kwargs)
          inner.perform(*args, **kwargs)
        end
      end
    RUBY

    info = result.dig("Wrapper", :perform)
    refute_nil info
    assert_equal :attr_send, info.receiver_kind
    assert_equal :inner, info.receiver_name
    assert_equal :perform, info.delegate_method
  end
end
