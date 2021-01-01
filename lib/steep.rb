require "steep/version"

require "pathname"
require "parser/ruby27"
require "ast_utils"
require "active_support/core_ext/object/try"
require "logger"
require "active_support/tagged_logging"
require "rainbow"
require "listen"
require 'language_server-protocol'
require "etc"
require "open3"
require "stringio"
require 'uri'

require "rbs"

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

require "steep/diagnostic/ruby"
require "steep/diagnostic/signature"
require "steep/signature/errors"
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

require "steep/server/utils"
require "steep/server/base_worker"
require "steep/server/code_worker"
require "steep/server/signature_worker"
require "steep/server/worker_process"
require "steep/server/interaction_worker"
require "steep/server/master"

require "steep/project"
require "steep/project/signature_file"
require "steep/project/source_file"
require "steep/project/options"
require "steep/project/target"
require "steep/project/dsl"
require "steep/project/file_loader"
require "steep/project/hover_content"
require "steep/project/completion_provider"
require "steep/project/stats_calculator"
require "steep/drivers/utils/driver_helper"
require "steep/drivers/check"
require "steep/drivers/stats"
require "steep/drivers/validate"
require "steep/drivers/annotations"
require "steep/drivers/watch"
require "steep/drivers/langserver"
require "steep/drivers/signature_error_printer"
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
      logger.level = prev_level || Logger::WARN
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

  def self.measure(message)
    start = Time.now
    yield.tap do
      time = Time.now - start
      self.logger.info "#{message} took #{time} seconds"
    end
  end

  def self.log_error(exn, message: "Unexpected error: #{exn.inspect}")
    Steep.logger.error message
    exn.backtrace.each do |loc|
      Steep.logger.warn "  #{loc}"
    end
  end
end
