# ALLOW FAILURE

new_1 = Regexp.new("a")
# !expects NoMethodError: type=::Regexp, method=foo
new_1.foo

new_2 = Regexp.new("a", true)
# !expects NoMethodError: type=::Regexp, method=foo
new_2.foo

new_3 = Regexp.new("a", Regexp::EXTENDED | Regexp::IGNORECASE)
# !expects NoMethodError: type=::Regexp, method=foo
new_3.foo

new_4 = Regexp.new(/a/)
# !expects NoMethodError: type=::Regexp, method=foo
new_4.foo

compile_1 = Regexp.compile("a")
# !expects NoMethodError: type=::Regexp, method=foo
compile_1.foo

compile_2 = Regexp.compile("a", true)
# !expects NoMethodError: type=::Regexp, method=foo
compile_2.foo

compile_3 = Regexp.compile("a", Regexp::EXTENDED | Regexp::IGNORECASE)
# !expects NoMethodError: type=::Regexp, method=foo
compile_3.foo

compile_4 = Regexp.compile(/a/)
# !expects NoMethodError: type=::Regexp, method=foo
compile_4.foo

escape_1 = Regexp.escape("a")
# !expects NoMethodError: type=::String, method=foo
escape_1.foo

last_match_1 = Regexp.last_match
# !expects NoMethodError: type=(::MatchData | nil), method=foo
last_match_1.foo

last_match_2 = Regexp.last_match(1)
# !expects NoMethodError: type=(::String | nil), method=foo
last_match_2.foo

quote_1 = Regexp.quote("a")
# !expects NoMethodError: type=::String, method=foo
quote_1.foo

try_convert_1 = Regexp.try_convert(Object.new)
# !expects NoMethodError: type=(::Regexp | nil), method=foo
try_convert_1.foo

union_1 = Regexp.union
# !expects NoMethodError: type=::Regexp, method=foo
union_1.foo

union_2 = Regexp.union("a")
# !expects NoMethodError: type=::Regexp, method=foo
union_2.foo

union_3 = Regexp.union("a", "b")
# !expects NoMethodError: type=::Regexp, method=foo
union_3.foo

union_4 = Regexp.union(["a", "b"])
# !expects NoMethodError: type=::Regexp, method=foo
union_4.foo

union_5 = Regexp.union(/a/)
# !expects NoMethodError: type=::Regexp, method=foo
union_5.foo

union_6 = Regexp.union(/a/, /b/)
# !expects NoMethodError: type=::Regexp, method=foo
union_6.foo

union_7 = Regexp.union([/a/, /b/])
# !expects NoMethodError: type=::Regexp, method=foo
union_7.foo

op_eqeqeq_1 = /a/ === "a"
# !expects NoMethodError: type=bool, method=foo
op_eqeqeq_1.foo

op_match_1 = /a/ =~ "a"
# !expects NoMethodError: type=::Integer, method=foo
op_match_1.foo

casefold_1 = /a/.casefold?
# !expects NoMethodError: type=bool, method=foo
casefold_1.foo

encoding_1 = /a/.encoding
# !expects NoMethodError: type=::Encoding, method=foo
encoding_1.foo

fixed_encoding_1 = /a/.fixed_encoding?
# !expects NoMethodError: type=bool, method=foo
fixed_encoding_1.foo

match_1 = /a/.match("a")
# !expects NoMethodError: type=(::MatchData | nil), method=foo
match_1.foo

match_2 = /a/.match("a", 0)
# !expects NoMethodError: type=(::MatchData | nil), method=foo
match_2.foo

/a/.match("a") do |m|
  # !expects NoMethodError: type=::MatchData, method=foo
  m.foo
end

/a/.match("a", 0) do |m|
  # !expects NoMethodError: type=::MatchData, method=foo
  m.foo
end

match_q_1 = /a/.match?("a")
# !expects NoMethodError: type=bool, method=foo
match_q_1.foo

match_q_2 = /a/.match?("a", 0)
# !expects NoMethodError: type=bool, method=foo
match_q_2.foo

named_captures_1 = /(?<foo>.)/.named_captures
# !expects NoMethodError: type=::Hash[::String, ::Array[::Integer]], method=foo
named_captures_1.foo

names_1 = /(?<foo>.)/.names
# !expects NoMethodError: type=::Array[::String], method=foo
names_1.foo

options_1 = /a/ix.options
# !expects NoMethodError: type=::Integer, method=foo
options_1.foo

source_1 = /a/ix.source
# !expects NoMethodError: type=::String, method=foo
source_1.foo

op_unary_match_1 = ~ /a/
# !expects NoMethodError: type=(::Integer | nil), method=foo
op_unary_match_1.foo
