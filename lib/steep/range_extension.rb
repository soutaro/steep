class RBS::Location
  def as_lsp_range
    {
      start: {
          line: start_line - 1,
          character: start_column
      },
      end: {
        line: end_line - 1,
        character: end_column
      }
    }
  end
end

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
