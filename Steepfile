require "fileutils"

D = Steep::Diagnostic

FileUtils.mkpath("tmp")
tmp_rbs_dir = Pathname("tmp/rbs-sig")

definition = Bundler::Definition.build(Pathname("Gemfile"), Pathname("Gemfile.lock"), nil)
rbs_dep = definition.dependencies.find {|dep| dep.name == "rbs" }
if (source = rbs_dep&.source).is_a?(Bundler::Source::Path)
  unless tmp_rbs_dir.directory?
    FileUtils.ln_s(Pathname.pwd + source.path + "sig", tmp_rbs_dir.to_s, force: true)
  end
else
  FileUtils.rm_f(tmp_rbs_dir)
end

target :app do
  collection_config "rbs_collection.steep.yaml"

  check "lib"
  ignore "lib/steep/shims"

  signature "sig"
  ignore_signature "sig/test"

  implicitly_returns_nil!

  configure_code_diagnostics(D::Ruby.strict) do |hash|
  end

  if tmp_rbs_dir.directory?
    signature tmp_rbs_dir.to_s
  else
    library "rbs"
  end
end

target :test do
  collection_config "rbs_collection.steep.yaml"

  unreferenced!
  implicitly_returns_nil!

  check "test"
  signature "sig/test"

  configure_code_diagnostics(D::Ruby.lenient)

  if tmp_rbs_dir.directory?
    signature tmp_rbs_dir.to_s
  else
    library "rbs"
  end
end

target :bin do
  unreferenced!
  implicitly_returns_nil!

  collection_config "rbs_collection.steep.yaml"

  check "bin/generate-diagnostics-docs.rb"
  signature "tmp/rbs-inline/bin"

  if tmp_rbs_dir.directory?
    signature tmp_rbs_dir.to_s
  else
    library "rbs"
  end
end
