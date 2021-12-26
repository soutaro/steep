require "steep/version"

require "pathname"
require "parser/ruby30"
require "active_support"
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

require "parallel/processor_count"
require "terminal-table"

require "rbs"

require "steep/equatable"
require "steep/method_name"
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
require "steep/ast/type_params"
require "steep/ast/annotation"
require "steep/ast/annotation/collection"
require "steep/ast/builtin"
require "steep/ast/types/factory"

require "steep/range_extension"

require "steep/interface/function"
require "steep/interface/block"
require "steep/interface/method_type"
require "steep/interface/substitution"
require "steep/interface/interface"

require "steep/subtyping/check"
require "steep/subtyping/result"
require "steep/subtyping/relation"
require "steep/subtyping/trace"
require "steep/subtyping/constraints"
require "steep/subtyping/variable_variance"
require "steep/subtyping/variable_occurrence"

require "steep/diagnostic/helper"
require "steep/diagnostic/ruby"
require "steep/diagnostic/signature"
require "steep/diagnostic/lsp_formatter"
require "steep/signature/validator"
require "steep/source"
require "steep/annotation_parser"
require "steep/typing"
require "steep/module_helper"
require "steep/type_construction"
require "steep/type_inference/context"
require "steep/type_inference/context_array"
require "steep/type_inference/send_args"
require "steep/type_inference/block_params"
require "steep/type_inference/method_params"
require "steep/type_inference/constant_env"
require "steep/type_inference/type_env"
require "steep/type_inference/local_variable_type_env"
require "steep/type_inference/logic"
require "steep/type_inference/logic_type_interpreter"
require "steep/type_inference/method_call"
require "steep/ast/types"

require "steep/index/rbs_index"
require "steep/index/signature_symbol_provider"
require "steep/index/source_index"

require "steep/server/change_buffer"
require "steep/server/base_worker"
require "steep/server/worker_process"
require "steep/server/interaction_worker"
require "steep/server/type_check_worker"
require "steep/server/master"

require "steep/services/content_change"
require "steep/services/path_assignment"
require "steep/services/signature_service"
require "steep/services/type_check_service"
require "steep/services/hover_content"
require "steep/services/completion_provider"
require "steep/services/stats_calculator"
require "steep/services/file_loader"
require "steep/services/goto_service"

require "steep/project"
require "steep/project/pattern"
require "steep/project/options"
require "steep/project/target"
require "steep/project/dsl"

require "steep/expectations"
require "steep/drivers/utils/driver_helper"
require "steep/drivers/utils/jobs_count"
require "steep/drivers/check"
require "steep/drivers/stats"
require "steep/drivers/validate"
require "steep/drivers/annotations"
require "steep/drivers/watch"
require "steep/drivers/langserver"
require "steep/drivers/trace_printer"
require "steep/drivers/print_project"
require "steep/drivers/init"
require "steep/drivers/vendor"
require "steep/drivers/worker"
require "steep/drivers/diagnostic_printer"

if ENV["NO_COLOR"]
  Rainbow.enabled = false
end

$stderr = STDERR

module Steep
  def self.logger
    @logger
  end

  def self.new_logger(output, prev_level)
    ActiveSupport::TaggedLogging.new(Logger.new(output)).tap do |logger|
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
  end

  @logger = nil
  self.log_output = STDERR

  def self.measure(message, level: :warn)
    start = Time.now
    yield.tap do
      time = Time.now - start
      if level.is_a?(Symbol)
        level = Logger.const_get(level.to_s.upcase)
      end
      self.logger.log(level) { "#{message} took #{time} seconds" }
    end
  end

  def self.log_error(exn, message: "Unexpected error: #{exn.inspect}")
    Steep.logger.fatal message
    exn.backtrace.each do |loc|
      Steep.logger.error "  #{loc}"
    end
  end

  class Sampler
    def initialize()
      @samples = []
    end

    def sample(message)
      start = Time.now
      yield.tap do
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
        0
      end
    end

    def percentile(p)
      slowests([count * p / 100r, 1].max).last&.last || 0
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
