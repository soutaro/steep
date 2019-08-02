/(?<foo>a)/.match("a") do |match|
  match_ref_1 = match[0]
  # !expects NoMethodError: type=(::String | nil), method=foo
  match_ref_1.foo

  match_ref_2 = match["foo"]
  # !expects NoMethodError: type=(::String | nil), method=foo
  match_ref_2.foo

  match_ref_3 = match[:foo]
  # !expects NoMethodError: type=(::String | nil), method=foo
  match_ref_3.foo

  match_ref_4 = match[0, 1]
  # !expects NoMethodError: type=::Array[::String], method=foo
  match_ref_4.foo

  match_ref_5 = match[0..1]
  # !expects NoMethodError: type=::Array[::String], method=foo
  match_ref_5.foo

  begin_1 = match.begin(0)
  # !expects NoMethodError: type=(::Integer | nil), method=foo
  begin_1.foo

  begin_2 = match.begin("foo")
  # !expects NoMethodError: type=::Integer, method=foo
  begin_2.foo

  begin_3 = match.begin(:foo)
  # !expects NoMethodError: type=::Integer, method=foo
  begin_3.foo

  captures_1 = match.captures
  # !expects NoMethodError: type=::Array[::String], method=foo
  captures_1.foo

  end_1 = match.end(0)
  # !expects NoMethodError: type=::Integer, method=foo
  end_1.foo

  end_2 = match.end("foo")
  # !expects NoMethodError: type=::Integer, method=foo
  end_2.foo

  end_3 = match.end(:foo)
  # !expects NoMethodError: type=::Integer, method=foo
  end_3.foo

  length_1 = match.length
  # !expects NoMethodError: type=::Integer, method=foo
  length_1.foo

  named_captures_1 = match.named_captures
  # !expects NoMethodError: type=::Hash[::String, (::String | nil)], method=foo
  named_captures_1.foo

  names_1 = match.names
  # !expects NoMethodError: type=::Array[::String], method=foo
  names_1.foo

  offset_1 = match.offset(0)
  # !expects NoMethodError: type=[::Integer, ::Integer], method=foo
  offset_1.foo

  offset_2 = match.offset("foo")
  # !expects NoMethodError: type=[::Integer, ::Integer], method=foo
  offset_2.foo

  offset_3 = match.offset(:foo)
  # !expects NoMethodError: type=[::Integer, ::Integer], method=foo
  offset_3.foo

  post_match_1 = match.post_match
  # !expects NoMethodError: type=::String, method=foo
  post_match_1.foo

  pre_match_1 = match.pre_match
  # !expects NoMethodError: type=::String, method=foo
  pre_match_1.foo

  regexp_1 = match.regexp
  # !expects NoMethodError: type=::Regexp, method=foo
  regexp_1.foo

  size_1 = match.size
  # !expects NoMethodError: type=::Integer, method=foo
  size_1.foo

  string_1 = match.string
  # !expects NoMethodError: type=::String, method=foo
  string_1.foo

  to_a_1 = match.to_a
  # !expects NoMethodError: type=::Array[::String], method=foo
  to_a_1.foo

  values_at_1 = match.values_at
  # !expects NoMethodError: type=::Array[(::String | nil)], method=foo
  values_at_1.foo

  values_at_2 = match.values_at(0, "foo", :foo)
  # !expects NoMethodError: type=::Array[(::String | nil)], method=foo
  values_at_2.foo
end
