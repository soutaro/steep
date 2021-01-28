class Parser::Source::Range
  def as_lsp_range
    {
      start: {
        line: line - 1,
        character: column
      },
      end: {
        line: last_line - 1,
        character: last_column
      }
    }
  end
end
