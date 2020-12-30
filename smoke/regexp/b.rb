/(?<foo>a)/.match("a") do |match|
  match_ref_1 = match[0]
  match_ref_1.foo

  match_ref_2 = match["foo"]
  match_ref_2.foo

  match_ref_3 = match[:foo]
  match_ref_3.foo

  match_ref_4 = match[0, 1]
  match_ref_4.foo

  match_ref_5 = match[0..1]
  match_ref_5.foo

  begin_1 = match.begin(0)
  begin_1.foo

  begin_2 = match.begin("foo")
  begin_2.foo

  begin_3 = match.begin(:foo)
  begin_3.foo

  captures_1 = match.captures
  captures_1.foo

  end_1 = match.end(0)
  end_1.foo

  end_2 = match.end("foo")
  end_2.foo

  end_3 = match.end(:foo)
  end_3.foo

  length_1 = match.length
  length_1.foo

  named_captures_1 = match.named_captures
  named_captures_1.foo

  names_1 = match.names
  names_1.foo

  offset_1 = match.offset(0)
  offset_1.foo

  offset_2 = match.offset("foo")
  offset_2.foo

  offset_3 = match.offset(:foo)
  offset_3.foo

  post_match_1 = match.post_match
  post_match_1.foo

  pre_match_1 = match.pre_match
  pre_match_1.foo

  regexp_1 = match.regexp
  regexp_1.foo

  size_1 = match.size
  size_1.foo

  string_1 = match.string
  string_1.foo

  to_a_1 = match.to_a
  to_a_1.foo

  values_at_1 = match.values_at
  values_at_1.foo

  values_at_2 = match.values_at(0, "foo", :foo)
  values_at_2.foo
end
