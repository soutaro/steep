D = Steep::Diagnostic

target :app do
  check "lib"
  ignore "lib/steep/shims"

  signature "sig"

  collection_config "rbs_collection.steep.yaml"

  configure_code_diagnostics(D::Ruby.strict) do |hash|
  end

  FileUtils.mkpath("tmp")
  tmp_rbs_dir = File.join("tmp", "rbs-sig")

  definition = Bundler::Definition.build(Pathname("Gemfile"), Pathname("Gemfile.lock"), nil)
  rbs_dep = definition.dependencies.find {|dep| dep.name == "rbs" }
  if (source = rbs_dep&.source).is_a?(Bundler::Source::Path)
    unless Pathname(tmp_rbs_dir).exist?
      FileUtils.ln_s(Pathname.pwd + source.path + "sig", tmp_rbs_dir, force: true)
    end
    signature tmp_rbs_dir
  else
    FileUtils.rm_f(tmp_rbs_dir)
    library "rbs"
  end

  library(
    "rdoc",
    "monitor",
    "tsort",
    "uri",
    'yaml',
    'pstore',
    'singleton',
    'shellwords',
    'find',
    'digest',
    "optparse",
  )
end
