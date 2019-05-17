class Pathname
end

class Time
  def self.now: -> instance
  def < : (Time) -> bool
  def >=: (Time) -> bool
end

type annotation = any

class Steep::Source
  def self.parse: (String, path: String, labeling: any) -> instance
  def annotations: (block: any, builder: any, current_module: any) -> Array<annotation>
  def node: -> any
  def find_node: (line: Integer, column: Integer) -> any
end

class Steep::Typing
  attr_reader errors: Array<type_error>
  attr_reader nodes: any
end

type type_error = any

class Steep::Project::Options
  attr_accessor fallback_any_is_error: bool
  attr_accessor allow_missing_definitions: bool
end

class Parser::SyntaxError
end

class Steep::Project::SourceFile
  attr_reader options: Options
  attr_reader path: Pathname
  attr_accessor content: String
  attr_reader content_updated_at: Time

  attr_reader source: (Source | Parser::SyntaxError | nil)
  attr_reader typing: Typing?
  attr_reader last_type_checked_at: Time?

  def initialize: (path: Pathname, options: Options) -> any
  def requires_type_check?: -> bool
  def invalidate: -> void
  def parse: -> (Source | Parser::SyntaxError)
  def errors: -> Array<type_error>?
  def type_check: (any) -> void
end

class Steep::Project::SignatureFile
  attr_reader path: Pathname
  attr_accessor content: String
  attr_reader content_updated_at: Time

  def parse: -> Array<any>
end

interface Steep::Project::_Listener
  def parse_signature: <'x> (project: Project, file: SignatureFile) { -> 'x } -> 'x
  def parse_source: <'x> (project: Project, file: SourceFile) { -> 'x } -> 'x
  def check: <'x> (project: Project) { -> 'x } -> 'x
  def load_signature: <'x> (project: Project) { -> 'x } -> 'x
  def validate_signature: <'x> (project: Project) { -> 'x } -> 'x
  def type_check_source: <'x> (project: Project, file: SourceFile) { -> 'x } -> 'x
  def clear_project: <'x> (project: Project) { -> 'x } -> 'x
end

class Steep::Project::SignatureLoaded
  attr_reader check: any
  attr_reader loaded_at: Time
  attr_reader file_paths: Array<Pathname>

  def initialize: (check: any, loaded_at: Time, file_paths: Array<Pathname>) -> any
end

class Steep::Project::SignatureHasSyntaxError
  attr_reader errors: Hash<Pathname, any>
  def initialize: (errors: Hash<Pathname, any>) -> any
end

class Steep::Project::SignatureHasError
  attr_reader errors: Array<any>
  def initialize: (errors: Array<any>) -> any
end

class Steep::Project
  attr_reader listener: _Listener
  attr_reader source_files: Hash<Pathname, SourceFile>
  attr_reader signature_files: Hash<Pathname, SignatureFile>

  attr_reader signature: (SignatureLoaded | SignatureHasError | SignatureHasSyntaxError | nil)

  def initialize: (?_Listener?) -> any
  def clear: -> void
  def type_check: (?force_signatures: bool, ?force_sources: bool) -> void

  def success?: -> bool
  def has_type_error?: -> bool
  def errors: -> Array<type_error>
  def each_updated_source: (?force: bool) { (SourceFile) -> void } -> void
                         | (?force: bool) -> Enumerator<SourceFile, void>
  def signature_updated?: -> bool
  def reload_signature: -> void
  def validate_signature: (any) -> Array<any>

  def type_of: (path: Pathname, line: Integer, column: Integer) -> any
end
