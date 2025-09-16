require "steep/version"

require "pathname"
require "parser/ruby33"
require "prism"
require "active_support"
require "active_support/core_ext/object/try"
require "active_support/core_ext/string/inflections"
require "logger"
require "rainbow"
require "listen"
require 'language_server-protocol'
require "etc"
require "open3"
require "stringio"
require 'uri'
require "yaml"
require "securerandom"
require "base64"
require "time"
require 'socket'

require "concurrent/utility/processor_counter"
require "terminal-table"

require "rbs"

require "steep/path_helper"
require "steep/located_value"
require "steep/thread_waiter"
require "steep/equatable"
require "steep/method_name"
require "steep/node_helper"
require "steep/ast/types/shared_instance"
require "steep/ast/types/helper"
require "steep/ast/types/any"
require "steep/ast/types/instance"
require "steep/ast/types/class"
require "steep/ast/types/union"
require "steep/ast/types/var"
require "steep/ast/types/name"
require "steep/ast/types/self"
require "steep/ast/types/intersection"
require "steep/ast/types/void"
require "steep/ast/types/bot"
require "steep/ast/types/top"
require "steep/ast/types/nil"
require "steep/ast/types/literal"
require "steep/ast/types/boolean"
require "steep/ast/types/tuple"
require "steep/ast/types/proc"
require "steep/ast/types/record"
require "steep/ast/types/logic"
require "steep/ast/annotation"
require "steep/ast/annotation/collection"
require "steep/ast/node/type_assertion"
require "steep/ast/node/type_application"
require "steep/ast/builtin"
require "steep/ast/types/factory"
require "steep/ast/ignore"

require "steep/range_extension"

require "steep/interface/type_param"
require "steep/interface/function"
require "steep/interface/block"
require "steep/interface/method_type"
require "steep/interface/substitution"
require "steep/interface/shape"
require "steep/interface/builder"

require "steep/subtyping/result"
require "steep/subtyping/check"
require "steep/subtyping/cache"
require "steep/subtyping/relation"
require "steep/subtyping/constraints"
require "steep/subtyping/variable_variance"

require "steep/diagnostic/helper"
require "steep/diagnostic/result_printer2"
require "steep/diagnostic/ruby"
require "steep/diagnostic/signature"
require "steep/diagnostic/lsp_formatter"
require "steep/signature/validator"
require "steep/module_helper"
require "steep/source"
require "steep/source/ignore_ranges"
require "steep/annotation_parser"
require "steep/typing"
require "steep/type_construction"
require "steep/type_inference/context"
require "steep/type_inference/send_args"
require "steep/type_inference/block_params"
require "steep/type_inference/method_params"
require "steep/type_inference/constant_env"
require "steep/type_inference/type_env"
require "steep/type_inference/type_env_builder"
require "steep/type_inference/logic_type_interpreter"
require "steep/type_inference/multiple_assignment"
require "steep/type_inference/method_call"
require "steep/type_inference/case_when"

require "steep/locator.rb"

require "steep/index/rbs_index"
require "steep/index/signature_symbol_provider"
require "steep/index/source_index"

require "steep/services/content_change"
require "steep/services/path_assignment"
require "steep/services/signature_service"
require "steep/services/type_check_service"
require "steep/services/hover_provider/content"
require "steep/services/hover_provider/singleton_methods"
require "steep/services/hover_provider/ruby"
require "steep/services/hover_provider/rbs"
require "steep/services/completion_provider"
require "steep/services/completion_provider/type_name"
require "steep/services/completion_provider/ruby"
require "steep/services/completion_provider/rbs"
require "steep/services/signature_help_provider"
require "steep/services/stats_calculator"
require "steep/services/file_loader"
require "steep/services/goto_service"

require "steep/server/custom_methods"
require "steep/server/work_done_progress"
require "steep/server/delay_queue"
require "steep/server/lsp_formatter"
require "steep/server/change_buffer"
require "steep/server/base_worker"
require "steep/server/worker_process"
require "steep/server/interaction_worker"
require "steep/server/type_check_worker"
require "steep/server/target_group_files"
require "steep/server/type_check_controller"
require "steep/server/inline_source_change_detector"
require "steep/server/master"

require "steep/project"
require "steep/project/pattern"
require "steep/project/options"
require "steep/project/target"
require "steep/project/group"
require "steep/project/dsl"

require "steep/expectations"
require "steep/drivers/utils/driver_helper"
require "steep/drivers/utils/jobs_option"
require "steep/drivers/check"
require "steep/drivers/checkfile"
require "steep/drivers/stats"
require "steep/drivers/annotations"
require "steep/drivers/watch"
require "steep/drivers/langserver"
require "steep/drivers/print_project"
require "steep/drivers/init"
require "steep/drivers/vendor"
require "steep/drivers/worker"
require "steep/drivers/diagnostic_printer"
require "steep/drivers/diagnostic_printer/base_formatter"
require "steep/drivers/diagnostic_printer/code_formatter"
require "steep/drivers/diagnostic_printer/github_actions_formatter"

require "steep/annotations_helper"

if ENV["NO_COLOR"]
  Rainbow.enabled = false
end

$stderr = STDERR

module Steep
  def self.logger
    @logger || raise
  end

  def self.ui_logger
    @ui_logger || raise
  end

  def self.new_logger(output, prev_level)
    logger = Logger.new(output)
    logger.formatter = proc do |severity, datetime, progname, msg|
      # @type var severity: String
      # @type var datetime: Time
      # @type var progname: untyped
      # @type var msg: untyped
      # @type block: String
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}: #{severity}: #{msg}\n"
    end
    ActiveSupport::TaggedLogging.new(logger).tap do |logger|
      logger.push_tags "Steep #{VERSION}"
      logger.level = prev_level || Logger::ERROR
    end
  end

  def self.log_output
    @log_output
  end

  def self.log_output=(output)
    @log_output = output

    prev_level = @logger&.level
    @logger = new_logger(output, prev_level)

    prev_level = @ui_logger&.level
    @ui_logger = new_logger(output, prev_level)

    output
  end

  @logger = nil
  @ui_logger = nil
  self.log_output = STDERR

  def self.measure(message, level: :warn, threshold: 0.0)
    start = Time.now
    begin
      yield
    ensure
      time = Time.now - start
      if level.is_a?(Symbol)
        level = Logger.const_get(level.to_s.upcase)
      end
      if time > threshold
        self.logger.log(level) { "#{message} took #{time} seconds" }
      end
    end
  end

  def self.log_error(exn, message: "Unexpected error: #{exn.inspect}")
    Steep.logger.fatal message
    if backtrace = exn.backtrace
      backtrace.each do |loc|
        Steep.logger.error "  #{loc}"
      end
    end
  end

  def self.can_fork?
    defined?(fork)
  end

  class Sampler
    def initialize()
      @samples = []
    end

    def sample(message)
      start = Time.now
      begin
        yield
      ensure
        time = Time.now - start
        @samples << [message, time]
      end
    end

    def count
      @samples.count
    end

    def total
      @samples.sum(&:last)
    end

    def slowests(num)
      @samples.sort_by(&:last).reverse.take(num)
    end

    def average
      if count > 0
        total/count
      else
        0.to_f
      end
    end

    def percentile(p)
      c = [count * p / 100.to_r, 1].max or raise
      slowests(c.to_i).last&.last || 0.to_f
    end
  end

  def self.measure2(message, level: :warn)
    sampler = Sampler.new
    result = yield(sampler)

    if level.is_a?(Symbol)
      level = Logger.const_get(level.to_s.upcase)
    end
    logger.log(level) { "#{sampler.total}secs for \"#{message}\"" }
    logger.log(level) { "  Average: #{sampler.average}secs"}
    logger.log(level) { "  Median: #{sampler.percentile(50)}secs"}
    logger.log(level) { "  Samples: #{sampler.count}"}
    logger.log(level) { "  99 percentile: #{sampler.percentile(99)}secs"}
    logger.log(level) { "  90 percentile: #{sampler.percentile(90)}secs"}
    logger.log(level) { "  10 Slowests:"}
    sampler.slowests(10).each do |message, time|
      logger.log(level) { "    #{message} (#{time}secs)"}
    end

    result
  end
end

# klasses = [
#   # Steep::Interface::MethodType
# ] #: Array[Class]
#
# klasses.each do |klass|
#   klass.instance_eval do
#     def self.new(*_a, **_b, &_c)
#       super
#     end
#   end
# end

module GCCounter
  module_function

  def count_objects(title, regexp = /^Steep/, skip: false)
    if ENV["COUNT_GC_OBJECTS"] && !skip
      unless GC.disable
        GC.start(immediate_sweep: true, immediate_mark: true, full_mark: true)

        begin
          yield
        ensure
          Steep.logger.fatal "===== #{title} ==============================="

          klasses = [] #: Array[Class]

          ObjectSpace.each_object(Class) do |klass|
            if (klass.name || "") =~ regexp
              klasses << klass
            end
          end

          before = {} #: Hash[Class, Integer]

          klasses.each do |klass|
            count = ObjectSpace.each_object(klass).count
            before[klass] = count
          end

          GC.start(immediate_sweep: true, immediate_mark: true, full_mark: true)

          gceds = [] #: Array[[Class, Integer]]

          klasses.each do |klass|
            count = ObjectSpace.each_object(klass).count
            gced = (before[klass] || 0) - count

            gceds << [klass, gced] if gced > 0
          end

          gceds.sort_by! {|_, count| -count }
          gceds.each do |klass, count|
            Steep.logger.fatal { "#{klass.name} => #{count}"}
          end

          GC.enable
        end
      else
        yield
      end
    else
      yield
    end
  end
end




# klasses = [Set]
# klasses.each do |klass|
#   # steep:ignore:start
#   def klass.new(...)
#     super
#   end
#   # steep:ignore:end
# end
