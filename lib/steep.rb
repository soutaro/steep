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
require "steep/ast/method_type"
require "steep/ast/type_params"
require "steep/ast/signature/class"
require "steep/ast/signature/module"
require "steep/ast/signature/members"
require "steep/ast/signature/extension"
require "steep/ast/signature/interface"
require "steep/ast/signature/env"
require "steep/ast/signature/const"
require "steep/ast/signature/gvar"
require "steep/ast/signature/alias"
require "steep/ast/annotation"
require "steep/ast/annotation/collection"
require "steep/ast/buffer"
require "steep/ast/builtin"

require "steep/interface/method_type"
require "steep/interface/method"
require "steep/interface/builder"
require "steep/interface/substitution"
require "steep/interface/abstract"
require "steep/interface/instantiated"
require "steep/interface/ivar_chain"

require "steep/subtyping/check"
require "steep/subtyping/result"
require "steep/subtyping/relation"
require "steep/subtyping/trace"
require "steep/subtyping/constraints"
require "steep/subtyping/variable_variance"
require "steep/subtyping/variable_occurrence"

require "steep/signature/errors"
require "steep/parser"
require "steep/source"
require "steep/typing"
require "steep/errors"
require "steep/type_construction"
require "steep/type_inference/send_args"
require "steep/type_inference/block_params"
require "steep/type_inference/constant_env"
require "steep/type_inference/type_env"

require "steep/project"
require "steep/project/file"
require "steep/project/listener"
require "steep/project/options"
require "steep/drivers/utils/each_signature"
require "steep/drivers/check"
require "steep/drivers/validate"
require "steep/drivers/annotations"
require "steep/drivers/scaffold"
require "steep/drivers/print_interface"
require "steep/drivers/watch"
require "steep/drivers/langserver"

if ENV["NO_COLOR"]
  Rainbow.enabled = false
end

module Steep
  def self.logger
    self.log_output = STDERR unless @logger

    @logger
  end

  def self.log_output=(output)
    prev_level = @logger&.level

    @logger = ActiveSupport::TaggedLogging.new(Logger.new(output))
    @logger.push_tags "Steep #{VERSION}"
    @logger.level = prev_level || Logger::WARN
  end
end
