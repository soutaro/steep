require "bundler/gem_tasks"
require "rake/testtask"

if ENV["VSCODE_CWD"]
  require "minitest"
  Minitest.seed = Time.now.to_i
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test

namespace :test do
  desc "Run output test"
  task :output do
    sh "ruby", "bin/output_test.rb"
  end

  namespace :output do
    desc "Run current output test"
    task :current do
      puts ">> Running `steep check` in #{ENV["PWD"]}"
      sh "steep", "check", "--with-expectations=test_expectations.yml", chdir: ENV["PWD"]
    end
  end
end

# Pull requests with one of these labels are omitted from the changelog.
CHANGELOG_SKIP_LABELS = ["skip-changelog"]

# The tags a release proper starts *after*, rather than at.
CHANGELOG_PRERELEASE_TAGS = ["v*.pre*", "v*.dev*"]

# Resolves the commit-ish the changelog of the release being prepared starts from.
#
# `version` is a version number, a tag, or any commit-ish. When it is omitted, the base follows
# `Steep::VERSION`:
#
# * `X.Y.Z.pre.N` documents what changed since `X.Y.Z.pre.N-1`, so it starts from the latest tag.
# * `X.Y.Z` documents the whole cycle, the prereleases included, so it skips the prerelease tags
#   in between and starts from the previous release proper.
#
# This is the step that is easy to get wrong by hand: on a release proper the latest tag is a
# prerelease, so the obvious default would produce only the tail of the cycle. Passing a version
# explicitly overrides all of it.
#
def changelog_base(version)
  require "open3"

  from =
    if version
      # `2.1.0` and `v2.1.0` both mean the tag `v2.1.0`, while `master` or a SHA is used as is.
      version.match?(/\A\d/) ? "v#{version}" : version
    else
      command = ["git", "describe", "--tags", "--match", "v*", "--abbrev=0"]
      unless Gem::Version.new(Steep::VERSION).prerelease?
        CHANGELOG_PRERELEASE_TAGS.each { |glob| command.push("--exclude", glob) }
      end

      output, status = Open3.capture2(*command)
      raise "🚨 Cannot detect the tag the changelog starts from. Give the previous version explicitly." unless status.success?
      output.chomp
    end

  _, status = Open3.capture2("git", "rev-parse", "--verify", "--quiet", "#{from}^{commit}")
  raise "🚨 No such commit-ish: `#{from}`" unless status.success?

  from
end

# Runs a GraphQL query against the repository of the working directory.
#
# `body` is the selection set inside `repository`, so a query can use the `$owner` and `$name`
# variables. Returns the contents of `data.repository`.
#
def changelog_graphql(body)
  require "open3"
  require "json"

  @changelog_repository ||=
    begin
      output, status = Open3.capture2("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
      raise status.inspect unless status.success?
      output.chomp.split("/", 2)
    end
  owner, name = @changelog_repository

  query = <<~GRAPHQL
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        #{body}
      }
    }
  GRAPHQL

  output, status = Open3.capture2(
    "gh", "api", "graphql",
    "-f", "query=#{query}",
    "-f", "owner=#{owner}",
    "-f", "name=#{name}",
    binmode: true
  )
  raise status.inspect unless status.success?

  # GitHub always answers in UTF-8, while the default external encoding follows the locale. Without
  # this, a pull request body with an emoji fails to parse under `LANG=C`, as in GitHub Actions.
  JSON.parse(output.force_encoding(Encoding::UTF_8), symbolize_names: true).dig(:data, :repository)
end

# Lists the commits between `from` and `HEAD`, newest first.
#
def changelog_commits(from)
  require "open3"

  output, status = Open3.capture2("git", "log", "--format=%H", "#{from}..HEAD")
  raise status.inspect unless status.success?

  output.lines.map(&:chomp).reject(&:empty?)
end

# What `git cherry-pick -x` appends to the message of the commit it creates.
CHERRY_PICK_ORIGIN = /^\(cherry picked from commit ([0-9a-f]{40})\)$/

# Maps the commits that record where they were cherry-picked from to that commit.
#
# A backport is a cherry-pick, so on a release branch it is the recorded origin, not the commit
# itself, that leads to the pull request the change was written and reviewed in. Without this a
# backported change is attributed to the pull request that carried the backport, which says
# nothing about the change and is the same for every commit it brought over.
#
# A commit backported twice -- the development line, then a release branch -- carries one line
# per hop, appended in order, so the first one is where the change started.
#
def changelog_origins(commits)
  return {} if commits.empty?

  require "open3"

  # `--no-walk` prints these commits and nothing else. NUL delimiters keep a commit message --
  # which can contain anything, including what this format looks like -- from being read as the
  # format itself.
  output, status = Open3.capture2("git", "log", "--no-walk", "--format=%H%x00%B%x00", *commits, binmode: true)
  raise status.inspect unless status.success?

  # Commit messages are UTF-8, while the default external encoding follows the locale. Without
  # this, splitting a message that is not ASCII fails under `LANG=C`, as in GitHub Actions.
  output.force_encoding(Encoding::UTF_8)

  output.split("\0").each_slice(2).each_with_object({}) do |(commit, message), origins|
    commit = commit.to_s.strip
    next if commit.empty?

    origin = message.to_s[CHERRY_PICK_ORIGIN, 1] or next
    origins[commit] = origin
  end
end

# Asks GitHub which pull requests each commit came from, so that any merge strategy -- merge
# commit, squash, or rebase -- is handled without parsing commit messages.
#
# Returns `{ oid => [pull request, ...] }`, with an empty array for the commits GitHub has no
# merged pull request for, including the ones it does not know at all.
#
def changelog_associated_pull_requests(oids)
  oids.uniq.each_slice(50).each_with_object({}) do |slice, found|
    aliases = slice.map.with_index do |oid, index|
      <<~GRAPHQL
        c#{index}: object(oid: "#{oid}") {
          ... on Commit {
            associatedPullRequests(first: 10) {
              nodes {
                number title url merged
                labels(first: 100) { nodes { name } }
              }
            }
          }
        }
      GRAPHQL
    end

    response = changelog_graphql(aliases.join("\n"))

    slice.each_with_index do |oid, index|
      nodes = response.dig(:"c#{index}", :associatedPullRequests, :nodes) || []

      found[oid] = nodes.select { |pr| pr[:merged] }.map do |pr|
        { number: pr[:number], title: pr[:title], url: pr[:url], labels: pr.dig(:labels, :nodes).map { |label| label[:name] } }
      end
    end
  end
end

# Finds the pull requests the commits came from, keeping the order of `commits`.
#
# Returns the pull requests for the changelog and the ones omitted by `skip_labels`.
#
def changelog_pull_requests(commits, skip_labels: CHANGELOG_SKIP_LABELS)
  origins = changelog_origins(commits)
  found = changelog_associated_pull_requests(commits.map { |commit| origins[commit] || commit })

  # An origin that leads nowhere -- a commit cherry-picked from a fork, or one that went to the
  # default branch without a pull request -- falls back to the commit in this history, which is
  # at least the backport that brought it here.
  fallbacks = commits.select { |commit| origins[commit] && found.fetch(origins[commit], []).empty? }
  found.update(changelog_associated_pull_requests(fallbacks)) unless fallbacks.empty?

  pull_requests = {}
  skipped = {}

  commits.each do |commit|
    prs = found.fetch(origins[commit] || commit, [])
    prs = found.fetch(commit, []) if prs.empty?

    prs.each do |pr|
      if (pr[:labels] & skip_labels).empty?
        pull_requests[pr[:number]] ||= pr
      else
        skipped[pr[:number]] ||= pr
      end
    end
  end

  [pull_requests.values, skipped.values]
end

# Fetches the details that help classifying the pull requests: the changed files and the body.
#
def changelog_pull_request_details(pull_requests)
  pull_requests.each_slice(50).flat_map do |slice|
    aliases = slice.map do |pr|
      <<~GRAPHQL
        p#{pr[:number]}: pullRequest(number: #{pr[:number]}) {
          body
          author { login }
          files(first: 100) {
            nodes { path }
            pageInfo { hasNextPage }
          }
        }
      GRAPHQL
    end

    details = changelog_graphql(aliases.join("\n"))

    slice.map do |pr|
      detail = details[:"p#{pr[:number]}"] or next pr

      pr.merge(
        author: detail.dig(:author, :login),
        # The body is a hint for writing the changelog, not a copy source. Keep it short.
        body: detail[:body].to_s.strip.slice(0, 1000),
        files: detail.dig(:files, :nodes).map { |file| file[:path] },
        files_truncated: detail.dig(:files, :pageInfo, :hasNextPage)
      )
    end
  end
end

# Reports the pull requests omitted by their label, so that they do not disappear silently.
#
def warn_skipped_pull_requests(skipped, skip_labels)
  return if skipped.empty?

  numbers = skipped.map { |pr| "##{pr[:number]}" }
  numbers = numbers.take(20).push("and #{numbers.size - 20} more") if numbers.size > 20

  $stderr.puts
  $stderr.puts "  (⏭️  Skipped #{skipped.size} pull request(s) labeled #{skip_labels.map { |label| "`#{label}`" }.join(" or ")}: #{numbers.join(", ")})"
end

# Prints the changelog template listing the pull requests merged between `from` and `HEAD`.
#
# The changelog goes to STDOUT and everything else goes to STDERR, so that the output can be
# piped to another command: `rake gem:changelog | pbcopy`
#
def print_changelog(from, skip_labels: CHANGELOG_SKIP_LABELS)
  $stderr.puts "🔍 Finding pull requests merged between `#{from}` and `HEAD`..."

  commits = changelog_commits(from)
  if commits.empty?
    $stderr.puts "  (🤔 There is no commit after `#{from}`.)"
    return
  end

  pull_requests, skipped = changelog_pull_requests(commits, skip_labels: skip_labels)

  if pull_requests.empty?
    $stderr.puts "  (🤔 No pull request is associated to the commits after `#{from}`.)"
  else
    $stderr.puts
    pull_requests.each do |pr|
      puts "* #{pr[:title]} ([##{pr[:number]}](#{pr[:url]}))"
    end
    $stdout.flush
  end

  warn_skipped_pull_requests(skipped, skip_labels)
end

# Prints the same pull requests as `print_changelog` as JSON, with the details that help
# classifying them into the sections of CHANGELOG.md.
#
# This is the input for the release automation, so it always prints a valid JSON document.
#
def print_changelog_json(from, skip_labels: CHANGELOG_SKIP_LABELS)
  require "json"

  $stderr.puts "🔍 Finding pull requests merged between `#{from}` and `HEAD`..."

  commits = changelog_commits(from)
  pull_requests, skipped = changelog_pull_requests(commits, skip_labels: skip_labels)
  pull_requests = changelog_pull_request_details(pull_requests)

  $stderr.puts "  (📋 #{pull_requests.size} pull request(s))"

  puts JSON.pretty_generate(
    {
      from: from,
      to: "HEAD",
      pull_requests: pull_requests,
      skipped: skipped
    }
  )
  $stdout.flush

  warn_skipped_pull_requests(skipped, skip_labels)
end

namespace :gem do
  desc "Generate changelog template from GH pull requests merged since the previous release"
  task :changelog, [:version] do |_task, args|
    print_changelog(changelog_base(args[:version]))
  end

  namespace :changelog do
    desc "Print the pull requests of `gem:changelog` as JSON, with the changed files and body of each"
    task :json, [:version] do |_task, args|
      print_changelog_json(changelog_base(args[:version]))
    end
  end

  # There are three kinds of release: `X.Y.Z`, `X.Y.Z.pre.N`, and `X.Y.Z.dev.N`. The
  # `.dev.N` ones are cut from the development line for people who need a specific
  # change early; they are not written up in the changelog, so there are no notes to
  # publish and nothing worth announcing.
  def dev_release?(version)
    Gem::Version.new(version).segments.include?("dev")
  end

  # The body of the topmost section of CHANGELOG.md, which is the release being
  # prepared, minus its own heading.
  #
  # The encoding is explicit because the default external encoding follows the
  # locale, and the changelog is not ASCII.
  #
  def changelog_section(version)
    content = File.read(File.join(__dir__, "CHANGELOG.md"), encoding: Encoding::UTF_8)
    section = content.scan(/^## \d.*?(?=^## \d)/m)[0] or raise "🚨 Cannot find a release section in CHANGELOG.md"
    heading, _, body = section.partition("\n")
    heading.include?(version) or raise "🚨 CHANGELOG.md starts with `#{heading.strip}`, which is not #{version}"
    body.strip
  end

  desc "Check that the working tree is ready to be released as the given version"
  task :check_release, [:version] do |_task, args|
    version = args[:version] or raise "🚨 Pass the version being released: `rake 'gem:check_release[2.1.0]'`"
    Gem::Version.correct?(version) or raise "🚨 `#{version}` is not a version number."

    # The version being released and the version the commit declares are stated
    # separately -- one by whoever starts the release, one by the commit itself --
    # so that releasing the wrong commit, or releasing the right one under the wrong
    # name, fails here rather than on RubyGems.
    version == Steep::VERSION or
      raise "🚨 Releasing #{version}, but this commit declares `Steep::VERSION = #{Steep::VERSION.inspect}`."

    if dev_release?(version)
      puts "✅ #{version} is the version of this commit. It is a dev release, so CHANGELOG.md is not checked."
    else
      changelog_section(version)
      puts "✅ #{version} is the version of this commit, and CHANGELOG.md documents it."
    end
  end

  desc "Create and push the `vX.Y.Z` tag for Steep::VERSION"
  task :tag do
    tag = "v#{Steep::VERSION}"

    # Annotated, so that the tag carries its own author and date rather than
    # borrowing the tagged commit's.
    sh "git", "tag", "--annotate", "--message", "Steep #{Steep::VERSION}", tag
    sh "git", "push", "origin", tag

    puts "🏷️  Pushed #{tag}."
  end

  desc "Publish the GitHub release for Steep::VERSION, unless it is a `.dev.` version"
  task :gh_release do
    require "open3"

    version = Gem::Version.new(Steep::VERSION)
    major, minor, *_ = Steep::VERSION.split(".")
    tag = "v#{Steep::VERSION}"

    if dev_release?(Steep::VERSION)
      puts "⏭️  #{Steep::VERSION} is a dev release, so there is no GitHub release to publish."
      next
    end

    # The release is created against an existing tag, so that the artifacts and the
    # notes describe a commit that is already immutable.
    _, status = Open3.capture2("git", "rev-parse", "--verify", "--quiet", "#{tag}^{commit}")
    raise "🚨 No such tag: `#{tag}`. Tag the release before creating the GitHub release." unless status.success?

    notes = <<~NOTES
      [Release note](https://github.com/soutaro/steep/wiki/Release-Note-#{major}.#{minor})

      #{changelog_section(Steep::VERSION)}
    NOTES

    # Published rather than drafted: the notes are the changelog section that was
    # already reviewed in the release pull request, so there is nothing left to edit.
    command = [
      "gh", "release", "create", tag,
      "--title=#{Steep::VERSION}",
      "--notes=#{notes}"
    ]
    command << "--prerelease" if version.prerelease?

    output, status = Open3.capture2(*command)
    raise "🚨 `gh release create` failed: #{status.inspect}" unless status.success?

    puts "📝 Released #{tag}: #{output.chomp}"
  end
end
namespace :rbs do
  task :watch do
    require "listen"
    listener = Listen.to('test') do |modified, added, removed|
      paths = (modified + added).map do
        Pathname(_1).relative_path_from(Pathname.pwd)
      end
      Bundler.with_unbundled_env do
        sh "bin/rbs-inline", "--opt-out", "--output=sig", *paths.map(&:to_s)
      end
    end
    listener.start
    begin
      sleep
    rescue Interrupt
      listener.stop
    end
  end

  task :generate do
    Bundler.with_unbundled_env do
      sh "bin/rbs-inline --opt-out --output=sig test"
      sh "bin/rbs-inline --opt-out --output=tmp/rbs-inline bin/generate-diagnostics-docs.rb"
    end
  end
end
