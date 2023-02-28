new_1 = Regexp.new("a")
new_1.foo

new_2 = Regexp.new("a", nil)
new_2.foo

new_3 = Regexp.new("a", Regexp::EXTENDED | Regexp::IGNORECASE)
new_3.foo

new_4 = Regexp.new(/a/)
new_4.foo

compile_1 = Regexp.compile("a")
compile_1.foo

compile_2 = Regexp.compile("a", false)
compile_2.foo

compile_3 = Regexp.compile("a", Regexp::EXTENDED | Regexp::IGNORECASE)
compile_3.foo

compile_4 = Regexp.compile(/a/)
compile_4.foo

escape_1 = Regexp.escape("a")
escape_1.foo

last_match_1 = Regexp.last_match
last_match_1.foo

last_match_2 = Regexp.last_match(1)
last_match_2.foo

quote_1 = Regexp.quote("a")
quote_1.foo

try_convert_1 = Regexp.try_convert(Object.new)
try_convert_1.foo

union_1 = Regexp.union
union_1.foo

union_2 = Regexp.union("a")
union_2.foo

union_3 = Regexp.union("a", "b")
union_3.foo

union_4 = Regexp.union(["a", "b"])
union_4.foo

union_5 = Regexp.union(/a/)
union_5.foo

union_6 = Regexp.union(/a/, /b/)
union_6.foo

union_7 = Regexp.union([/a/, /b/])
union_7.foo

op_eqeqeq_1 = /a/ === "a"
op_eqeqeq_1.foo

op_match_1 = /a/ =~ "a"
op_match_1.foo

casefold_1 = /a/.casefold?
casefold_1.foo

encoding_1 = /a/.encoding
encoding_1.foo

fixed_encoding_1 = /a/.fixed_encoding?
fixed_encoding_1.foo

match_1 = /a/.match("a")
match_1.foo

match_2 = /a/.match("a", 0)
match_2.foo

/a/.match("a") do |m|
  m.foo
end

/a/.match("a", 0) do |m|
  m.foo
end

match_q_1 = /a/.match?("a")
match_q_1.foo

match_q_2 = /a/.match?("a", 0)
match_q_2.foo

named_captures_1 = /(?<foo>.)/.named_captures
named_captures_1.foo

names_1 = /(?<foo>.)/.names
names_1.foo

options_1 = /a/ix.options
options_1.foo

source_1 = /a/ix.source
source_1.foo

op_unary_match_1 = ~ /a/
op_unary_match_1.foo
