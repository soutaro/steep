require "steep/version"

require "pathname"
require "parser/current"
require "ast_utils"
require "active_support/core_ext/object/try"
require "logger"
require "active_support/tagged_logging"

require "steep/module_name"
require "steep/ast/location"
require "steep/ast/types/any"
require "steep/ast/types/instance"
require "steep/ast/types/class"
require "steep/ast/types/union"
require "steep/ast/types/var"
require "steep/ast/types/name"
require "steep/ast/types/self"
require "steep/ast/types/intersection"
require "steep/ast/method_type"
require "steep/ast/type_params"
require "steep/ast/signature/class"
require "steep/ast/signature/module"
require "steep/ast/signature/members"
require "steep/ast/signature/extension"
require "steep/ast/signature/interface"
require "steep/ast/signature/env"
require "steep/ast/annotation"
require "steep/ast/annotation/collection"
require "steep/ast/buffer"

require "steep/type_name"

require "steep/interface/method_type"
require "steep/interface/method"
require "steep/interface/builder"
require "steep/interface/substitution"
require "steep/interface/abstract"
require "steep/interface/instantiated"

require "steep/subtyping/check"
require "steep/subtyping/result"
require "steep/subtyping/relation"
require "steep/subtyping/trace"
require "steep/subtyping/constraints"

require "steep/signature/errors"
require "steep/parser"
require "steep/source"
require "steep/typing"
require "steep/errors"
require "steep/type_construction"
require "steep/type_inference/send_args"
require "steep/type_inference/block_params"

require "steep/drivers/utils/validator"
require "steep/drivers/utils/each_signature"
require "steep/drivers/check"
require "steep/drivers/validate"

module Steep
  def self.logger
    unless @logger
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(STDERR))
      @logger.push_tags "Steep #{VERSION}"
      @logger.level = Logger::ERROR
    end

    @logger
  end
end
