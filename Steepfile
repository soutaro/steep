target :app do
  check "lib"
  signature "sig"

  collection_config "rbs_collection.steep.yaml"

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
