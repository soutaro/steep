D = Steep::Diagnostic

target :app do
  check "lib"
  signature "sig"

  collection_config "rbs_collection.steep.yaml"

  configure_code_diagnostics do |hash|             # You can setup everything yourself
    hash[D::Ruby::MethodDefinitionMissing] = :hint
  end

  signature "../rbs/sig", "../rbs/stdlib/rdoc/0"
  library(
    "set",
    "pathname",
    "json",
    "logger",
    "monitor",
    "tsort",
    "uri",
    'yaml',
    'dbm',
    'pstore',
    'singleton',
    'shellwords',
    'fileutils',
    'find',
    'digest',
    "strscan",
    "rubygems",
    "optparse",
    "securerandom",
    "csv"
  )
end
