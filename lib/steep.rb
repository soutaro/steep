require "steep/version"

require "pathname"
require "parser/ruby25"
require "ast_utils"
require "active_support/core_ext/object/try"
require "logger"
require "active_support/tagged_logging"
require "rainbow"
require "listen"
require 'pry'
require 'language_server-protocol'

require "ruby/signature"

require "steep/ast/namespace"
require "steep/names"
require "steep/ast/location"
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
require "steep/ast/type_params"
require "steep/ast/annotation"
require "steep/ast/annotation/collection"
require "steep/ast/buffer"
require "steep/ast/builtin"
require "steep/ast/types/factory"

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

require "steep/signature/errors"
require "steep/signature/validator"
require "steep/source"
require "steep/annotation_parser"
require "steep/typing"
require "steep/errors"
require "steep/type_construction"
require "steep/type_inference/send_args"
require "steep/type_inference/block_params"
require "steep/type_inference/constant_env"
require "steep/type_inference/type_env"
require "steep/ast/types"

require "steep/project"
require "steep/project/file"
require "steep/project/options"
require "steep/project/target"
require "steep/project/dsl"
require "steep/drivers/utils/driver_helper"
require "steep/drivers/check"
require "steep/drivers/validate"
require "steep/drivers/annotations"
require "steep/drivers/scaffold"
require "steep/drivers/print_interface"
require "steep/drivers/watch"
require "steep/drivers/langserver"
require "steep/drivers/signature_error_printer"
require "steep/drivers/trace_printer"
require "steep/drivers/print_project"

if ENV["NO_COLOR"]
  Rainbow.enabled = false
end

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

  self.log_output = STDERR
end
