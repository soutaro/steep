module Steep
  # A basic implementation of ActiveSupport::TaggedLogging.
  # Might be able to be replaced by plain logger in the future.
  # https://github.com/ruby/logger/pull/132
  class TaggedLogging < Logger
    def initialize(...)
      super
      self.formatter = proc do |severity, datetime, progname, msg|
        # @type var severity: String
        # @type var datetime: Time
        # @type var progname: untyped
        # @type var msg: untyped
        # @type block: String
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}: #{severity}: #{formatted_tags} #{msg}\n"
      end
      # A symbol key spares `Thread#[]` the interning of a string on every lookup, and the
      # type check tags every node it visits
      @thread_key = :"steep_tagged_logging_tags:#{object_id}"
      current_tags << "Steep #{VERSION}"
    end

    def tagged(tag)
      tags = current_tags
      tags << tag
      begin
        yield
      ensure
        tags.pop
      end
    end

    def current_tags
      Thread.current[@thread_key] ||= []
    end

    def push_tags(*tags)
      current_tags.concat(tags)
    end

    def formatted_tags
      current_tags.map do |tag|
        tag = tag.call if tag.is_a?(Proc)
        "[#{tag}]"
      end.join(" ")
    end
  end
end
