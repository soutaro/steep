require "time"

module Steep
  class Tracing
    class Trace
      attr_reader :id, :children, :context, :started_at, :stopped_at

      def initialize(id, context, started_at, stopped_at, children)
        @id = id
        @context = context
        @started_at = started_at
        @stopped_at = stopped_at
        @children = children
      end

      def total_duration
        stopped_at - started_at
      end

      def self_duration
        child_total = children.sum(0) { _1.total_duration } #: Float
        total_duration - child_total
      end
    end

    class OpenTrace
      attr_reader :id, :context, :started_at, :parent, :children

      def initialize(id, context, parent)
        @id = id
        @started_at = Time.now
        @context = context
        @parent = parent
        @children = []
      end

      def close
        Trace.new(id, context, started_at, Time.now, children)
      end

      def parent!
        parent or raise
      end

      def root?
        parent ? false : true
      end
    end

    attr_reader :name, :header, :prefix, :current
    attr_accessor :prefix

    def initialize(name:, root:, header:)
      @name = name
      @latest_id = 0
      @current = OpenTrace.new(fresh, root, nil)
      @header = header
    end

    def fresh
      @latest_id += 1
      @latest_id
    end

    def save()
      return unless prefix

      until current.root?
        pop()
      end

      prefix.mkpath
      filename = prefix + "#{Process.pid}--#{name}.csv"

      filename.write(
        CSV.generate do |csv|
          csv << ["ID", "Parent ID", *header, "Self duration", "Total duration", "Started at", "Stopped at"]

          each_trace(current.close, nil) do |trace, parent_id|
            csv << [
              trace.id,
              parent_id || "",
              *trace.context,
              sprintf("%.5f", trace.self_duration),
              sprintf("%.5f", trace.total_duration),
              trace.started_at.iso8601,
              trace.stopped_at.iso8601
            ]
          end
        end
      )
    end

    def each_trace(trace, parent_id, &block)
      yield trace, parent_id

      trace.children.each do
        each_trace(_1, trace.id, &block)
      end
    end

    def trace(context)
      push(context)
      yield
    ensure
      pop()
    end

    def push(context = nil, &block)
      return unless prefix

      if block
        context = yield
      end

      current = current()
      new = OpenTrace.new(fresh, context || raise, current)
      @current = new
    end

    def pop
      return unless prefix

      current = current()
      raise if current.root?

      closed = current.close()

      @current = current.parent!
      @current.children << closed
    end

    class <<self
      attr_reader :type_checking, :subtyping_solver, :shape_builder
    end

    @type_checking =
      _ = Tracing.new(
        name: "typechecking",
        header: ["File", "Node type", "Location", "Size", "Source"],
        root: ["--", :toplevel, "", "", ""],
      )
    @subtyping_solver =
      _ = Tracing.new(name: "subtyping_solver", header: ["Constraint"], root: ["--"])
    @shape_builder =
      _ = Tracing.new(name: "shape_builder", header: ["Type"], root: [_ = "--"])

    def self.setup(prefix)
      type_checking.prefix = prefix
      subtyping_solver.prefix = prefix
      shape_builder.prefix = prefix
    end

    def self.save
      type_checking.save
      subtyping_solver.save
      shape_builder.save
    end
  end
end
