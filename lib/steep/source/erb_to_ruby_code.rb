# frozen_string_literal: true

module Steep
  class Source
    # Converts ERB template code to Ruby code by replacing ERB tags with Ruby statements
    # and HTML content with spaces, preserving line numbers and basic spacing.
    #
    # Supports all ERB tag variations:
    # - `<% ruby_code %>` - execution tags
    # - `<%= ruby_code %>` - output tags
    # - `<%- ruby_code %>` - execution tags with leading whitespace control
    # - `<% ruby_code -%>` - execution tags with trailing whitespace control
    # - `<%- ruby_code -%>` - execution tags with both leading and trailing whitespace control
    #
    # Adds semicolons after each ERB tag to separate multiple statements on the same line,
    # except for comments (lines starting with #).
    module ErbToRubyCode
      ERB_TAG_PREFIX_POSITION_REGEX = /<%[-=]?/
      ERB_TAG_SUFIX_POSITION_REGEX = /%>/
      ERB_TAG_PREFIX_REGEX = /^<%[-=]?\s*/
      ERB_TAG_SUFFIX_REGEX = /\s*-?%>$/
      NON_NEWLINE_REGEX = /[^\n]/

      private_constant :ERB_TAG_PREFIX_POSITION_REGEX,
                       :ERB_TAG_SUFIX_POSITION_REGEX,
                       :ERB_TAG_SUFFIX_REGEX,
                       :NON_NEWLINE_REGEX

      class << self
        def convert(source_code)
          idx = 0

          while idx < source_code.length
            erb_tag_prefix_position = source_code.index(ERB_TAG_PREFIX_POSITION_REGEX, idx)
            break unless erb_tag_prefix_position

            replace_everything_before_erb_tag_with_whitespace(erb_tag_prefix_position:, idx:, source_code:)

            erb_tag_sufix_position = source_code.index(ERB_TAG_SUFIX_POSITION_REGEX, erb_tag_prefix_position)
            if erb_tag_sufix_position.nil?
              # Incomplete ERB tag, replace rest with spaces, preserving newlines
              remaining = source_code[erb_tag_prefix_position..]
              source_code[erb_tag_prefix_position..-1] = remaining&.gsub(NON_NEWLINE_REGEX, ' ') || ''
              break
            end

            erb_tag_full_content = source_code[erb_tag_prefix_position..(erb_tag_sufix_position + 1)]
            unless erb_tag_full_content
              raise 'Internal error: erb_tag_full_content should not be nil after finding start and end tags'
            end

            erb_tag_prefix_length = erb_tag_prefix_length(erb_tag_full_content:)
            erb_tag_sufix_length = erb_tag_sufix_length(erb_tag_full_content:)

            replacement_erb_tag = generate_replacement(erb_tag_full_content:, erb_tag_prefix_length:,
                                                       erb_tag_sufix_length:)

            source_code[erb_tag_prefix_position..(erb_tag_sufix_position + 1)] = replacement_erb_tag
            idx = erb_tag_prefix_position + replacement_erb_tag.length
          end

          replace_everything_after_erb_tag_with_whitespace(idx:, source_code:)
        end

        private

        def replace_everything_before_erb_tag_with_whitespace(erb_tag_prefix_position:, idx:, source_code:)
          before_erb = source_code[idx...erb_tag_prefix_position] || ''
          source_code[idx...erb_tag_prefix_position] = before_erb.gsub(NON_NEWLINE_REGEX, ' ')
        end

        def erb_tag_prefix_length(erb_tag_full_content:)
          tag_prefix_match = erb_tag_full_content.match(ERB_TAG_PREFIX_REGEX) or raise
          tag_prefix_string = tag_prefix_match[0] or raise

          tag_prefix_string.length
        end

        def erb_tag_sufix_length(erb_tag_full_content:)
          tag_suffix_match = erb_tag_full_content.match(ERB_TAG_SUFFIX_REGEX) or raise
          tag_suffix_string = tag_suffix_match[0] or raise

          tag_suffix_string.length
        end

        def generate_replacement(erb_tag_full_content:, erb_tag_prefix_length:, erb_tag_sufix_length:)
          inner_with_tags_removed = inner_with_tags_removed(erb_tag_full_content:, erb_tag_prefix_length:,
                                                            erb_tag_sufix_length:)

          if inner_with_tags_removed.start_with?('#')
            (' ' * erb_tag_prefix_length) + inner_with_tags_removed + (' ' * erb_tag_sufix_length)
          else
            "#{' ' * erb_tag_prefix_length}#{inner_with_tags_removed}#{' ' * (erb_tag_sufix_length - 1)};"
          end
        end

        def inner_with_tags_removed(erb_tag_full_content:, erb_tag_prefix_length:, erb_tag_sufix_length:)
          erb_tag_full_content[erb_tag_prefix_length...-erb_tag_sufix_length] or raise
        end

        def replace_everything_after_erb_tag_with_whitespace(idx:, source_code:)
          return source_code if idx >= source_code.length

          remaining = source_code[idx..]
          source_code[idx..-1] = remaining&.gsub(NON_NEWLINE_REGEX, ' ') || ''

          source_code
        end
      end
    end
  end
end
