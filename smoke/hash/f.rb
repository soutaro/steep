# @type method commit: (Hash[Symbol, String?]) -> { repo: String, branch: String?, tag: String?, commit: String? }?
def commit(hash)
  if repo = hash[:foo]
    {
      repo: repo,
      branch: hash[:bar],
      tag: hash[:baz],
      commit: hash[:commit]
    }
  end
end
