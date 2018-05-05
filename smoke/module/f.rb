# !expects@+2 MethodDefinitionMissing: module=::Palette, method=self.nestopia_palette
# !expects@+1 UnexpectedDynamicMethod: module=::Palette, method=nestopia_palette
module Palette
  module_function

  # @dynamic self.defacto_palette

  def defacto_palette
    []
  end

  # @dynamic nestopia_palette
end
