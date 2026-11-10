# frozen_string_literal: true

# Generates doc/ast_nodes.yml, the specification of Steep's AST nodes, from
# the node definitions of Prism (config.yml in the prism gem).
#
#   $ ruby doc/generate_ast_nodes.rb > doc/ast_nodes.yml
#
# Steep's AST follows Prism's node structure. This script copies the nodes,
# their fields and flags from Prism's config.yml, and applies the differences
# of Steep's AST declared below.

require "yaml"

require "prism"
PRISM_SPEC = Gem.loaded_specs.fetch("prism")
CONFIG = YAML.load_file(File.join(PRISM_SPEC.gem_dir, "config.yml"))

# Nodes of Prism that Steep's AST doesn't have.
DROPPED_NODES = {
  "ErrorRecoveryNode" => "Steep は構文エラーのあるファイルを型検査しない(all_errors_are_fatal)。LSP で error tolerant にする場合に再検討。",
}

# Fields of Prism that Steep's AST doesn't have (node name => field names, or :all).
DROPPED_FIELDS = {
  "locals" => :all,   # Steep は TypeEnv でローカル変数を自前で管理する
  "depth" => :all,    # 同上
}

# Flag values of Prism that Steep's AST keeps (flags name => value name => category).
#
#   syntax  -- distinguishes syntax that the parser gem represented as separate node kinds or children
#   derived -- a summary computable from the syntax
#
# The other values (forced encodings, frozen string literals, integer bases and shareable constant
# modes) are for compilers and are dropped. A flags name with no value kept is dropped from its nodes.
KEPT_FLAGS = {
  "ArgumentsNodeFlags" => {
    "CONTAINS_FORWARDING" => "derived",
    "CONTAINS_KEYWORDS" => "derived",
    "CONTAINS_KEYWORD_SPLAT" => "derived",
    "CONTAINS_SPLAT" => "derived",
    "CONTAINS_MULTIPLE_SPLATS" => "derived",
  },
  "ArrayNodeFlags" => { "CONTAINS_SPLAT" => "derived" },
  "CallNodeFlags" => {
    "SAFE_NAVIGATION" => "syntax",
    "VARIABLE_CALL" => "derived",
    "ATTRIBUTE_WRITE" => "syntax",
    "IGNORE_VISIBILITY" => "derived",
  },
  "KeywordHashNodeFlags" => { "SYMBOL_KEYS" => "derived" },
  "LoopFlags" => { "BEGIN_MODIFIER" => "syntax" },
  "ParameterFlags" => { "REPEATED_PARAMETER" => "derived" },
  "ParenthesesNodeFlags" => { "MULTIPLE_STATEMENTS" => "derived" },
  "RangeFlags" => { "EXCLUDE_END" => "syntax" },
  "RegularExpressionFlags" => %w[IGNORE_CASE EXTENDED MULTI_LINE ONCE EUC_JP ASCII_8BIT WINDOWS_31J UTF_8].to_h { [_1, "syntax"] },
}

FLAG_NOTES = {
  "CallNodeFlags::SAFE_NAVIGATION" => "parser の csend。",
  "CallNodeFlags::VARIABLE_CALL" => "レシーバも引数も括弧も無い `foo`。ローカル変数だったかもしれない呼び出しで、補完やホバーで使える。",
  "CallNodeFlags::ATTRIBUTE_WRITE" => "`a.b = 1` / `a[1] = 2`。式の値はメソッドの戻り値ではなく右辺。",
  "CallNodeFlags::IGNORE_VISIBILITY" => "レシーバが無いか `self` の呼び出し。NodeHelper#private_send? を置き換える。",
  "RangeFlags::EXCLUDE_END" => "parser の erange / eflipflop。",
  "LoopFlags::BEGIN_MODIFIER" => "parser の while_post / until_post(`begin ... end while cond`)。",
  "RegularExpressionFlags::IGNORE_CASE" => "parser の regopt の子(`:i`)。他の正規表現オプション(x m o e n s u)も同様。",
  "ParameterFlags::REPEATED_PARAMETER" => "`_` のように同じ名前が繰り返されたパラメータ。",
}

# Prism's `type` => Ruby type in Steep.
TYPE_MAPPING = {
  "node" => "Node(抽象基底。kind があればそのクラス)",
  "node?" => "Node?",
  "node[]" => "Array[Node]",
  "constant" => "Symbol",
  "constant?" => "Symbol?",
  "constant[]" => "Array[Symbol]",
  "string" => "String",
  "integer" => "Integer",
  "double" => "Float",
  "uint8" => "Integer",
  "uint32" => "Integer",
  "location" => "RBS::Location(flat。<Name>::Location のフィールドになる)",
  "location?" => "RBS::Location?(同上)",
  "annotation[]" => "Array[annotation](Steep 独自。annotations セクションのクラスの和)",
  "TypeAssertion" => "Steep::AST::TypeAssertion(Steep 独自。annotations セクション)",
  "TypeApplication" => "Steep::AST::TypeApplication(Steep 独自。annotations セクション)",
}

# Nodes that TypeConstruction doesn't type check today (UnsupportedSyntax).
UNSUPPORTED = %w[
  CaseMatchNode InNode ArrayPatternNode HashPatternNode FindPatternNode AlternationPatternNode
  CapturePatternNode PinnedVariableNode PinnedExpressionNode MatchPredicateNode MatchRequiredNode
  FlipFlopNode MatchLastLineNode InterpolatedMatchLastLineNode NoBlockParameterNode
  PreExecutionNode PostExecutionNode RedoNode UndefNode
  BlockLocalVariableNode NoKeywordsParameterNode
]

# Fields whose StatementsNode (or body) is always present in Steep's AST, even when it is empty,
# so that block annotations always have a node to be attached to.
ALWAYS_PRESENT_BODIES = {
  "ProgramNode" => %w[statements],
  "IfNode" => %w[statements],
  "UnlessNode" => %w[statements],
  "ElseNode" => %w[statements],
  "WhileNode" => %w[statements],
  "UntilNode" => %w[statements],
  "ForNode" => %w[statements],
  "WhenNode" => %w[statements],
  "InNode" => %w[statements],
  "BeginNode" => %w[statements],
  "RescueNode" => %w[statements],
  "EnsureNode" => %w[statements],
  "PreExecutionNode" => %w[statements],
  "PostExecutionNode" => %w[statements],
  "DefNode" => %w[body],
  "ClassNode" => %w[body],
  "ModuleNode" => %w[body],
  "SingletonClassNode" => %w[body],
  "BlockNode" => %w[body],
  "LambdaNode" => %w[body],
}

# Fields added by Steep (node name => fields).
HEREDOC_BODY_FIELD = {
  "name" => "heredoc_body_loc",
  "type" => "location?",
  "comment" => "ヒアドキュメントの本文(開始記号の次の行から終端記号の直前まで)。ヒアドキュメントでなければ nil。expression は開始記号 `<<~EOS` だけを指すので、本文の中の位置はこれで判定する。",
}

ADDED_FIELDS = {
  "StatementsNode" => [
    { "name" => "annotations", "type" => "annotation[]", "comment" => "この文の並びの region に書かれたブロックアノテーション(`@type var` など)。" },
    { "name" => "region_loc", "type" => "location", "comment" => "この文の並びが書かれるテキスト上の領域(region)。`if foo` の then 節なら、条件の直後から `else` / `elsif` / `end` の直前まで。文の範囲(expression)とは一致しない。定義は regions セクション。" },
  ],
  "StringNode" => [HEREDOC_BODY_FIELD.dup],
  "InterpolatedStringNode" => [HEREDOC_BODY_FIELD.dup],
  "XStringNode" => [HEREDOC_BODY_FIELD.dup],
  "InterpolatedXStringNode" => [HEREDOC_BODY_FIELD.dup],
}

STEEP_NOTES = {
  "ProgramNode" => [
    "statements は空でも StatementsNode として常に存在する。トップレベルのアノテーションと、どこにも付かなかったアノテーションは statements.annotations に入る(現状の mapping[root] 相当)。",
    "comments と steep:ignore は Source 側に残す(木には入れない)。",
  ],
  "StatementsNode" => [
    "Steep の AST では本体を表すすべての位置に常に存在し(空の本体は body が空)、ブロックアノテーションの唯一の付与先になる。",
    "位置を 2 つ持つ。location.expression は Prism と同じく最初の文から最後の文まで(空のときは region の開始位置の空範囲)。location.region は本体が書かれるテキスト上の領域で、空行やコメントを含む。",
    "例: `if foo\\n  something()\\nend` の then 節は、expression が `something()`、region が `foo` の直後から `end` の直前まで。",
    "現状の mapping / construct_mapping は、コメントを含む最も内側の region の StatementsNode に付ける処理に置き換わる(annotation_attachment)。",
  ],
  "ElseNode" => ["Prism の ElseNode の expression は、else 節を閉じるキーワード(if / case の `end`、begin の中では次の `ensure` または `end`)まで含む。本体の領域は statements.region を見る。"],
  "EnsureNode" => ["expression は親の `end` まで含む(Prism の規約)。"],
  "WhenNode" => ["expression は最後の文で終わり、その後ろの空行やコメントは含まない。statements.region は次の `when` / `else` / `end` の直前まで伸びるので、位置からノードを探すときは region も見る(regions セクションの locator)。"],
  "IfNode" => [
  "`elsif` の IfNode の expression は外側の `end` まで含む(Prism の規約)。",
    "parser の `(if cond then else)` と、修飾子形式、三項演算子を 1 クラスで表す。三項演算子は if_keyword_loc が nil、then_keyword_loc が `?`、subsequent が ElseNode(else_keyword_loc が `:`)。",
    "`unless` は UnlessNode になる(parser は then/else を入れ替えた if にしていた)。`elsif` は subsequent の IfNode。",
    "現状の then_annotations / else_annotations は statements.annotations / subsequent.statements.annotations になる。",
  ],
  "UnlessNode" => ["parser では `if` ノードだった。TypeConstruction の if の分岐を共有するか、UnlessNode 用の分岐を持つか(真偽の反転)。"],
  "CallNode" => [
    "parser の send / csend / block / numblock / itblock を 1 クラスで表す。ブロックは block フィールド(BlockNode | BlockArgumentNode)、`&.` は CallNodeFlags::SAFE_NAVIGATION。",
    "`a[1]` は name が `:[]` で opening_loc / closing_loc が括弧、message_loc は `[1]` 全体(parser の selector と同じ)。`a.()` は name が `:call` で message_loc が nil。`!a` / `not a` は name が `:!`。",
    "TypeApplicationNode(`#$ Type`)はこのノードに付く。",
    "synthesize_sendish / deconstruct_sendish_and_block_nodes が不要になる。",
  ],
  "BlockNode" => [
    "parameters は BlockParametersNode | NumberedParametersNode | ItParametersNode | nil。numblock / itblock のノード種は無くなる。",
    "body は StatementsNode か、rescue / ensure を含むときは BeginNode。常に存在する(空でも StatementsNode)。ブロックのアノテーション(`@type block` など)は body(または body.statements)の annotations に入る。",
  ],
  "BlockParametersNode" => [
    "parser の procarg0(`|a|` の自動 splat)に対応するノードは無い。requireds が 1 つだけで他が空、かつ rest が ImplicitRestNode でないとき(`|a,|` ではない)に procarg0 相当と判定する。`|(a, b)|` は requireds に MultiTargetNode。",
  ],
  "LambdaNode" => ["parser では `(block (lambda) args body)` だった。CallNode ではなく独立したノード。"],
  "BeginNode" => [
    "parser の kwbegin / rescue / resbody / ensure の入れ子を、rescue_clause / else_clause / ensure_clause のフィールドで平坦に表す。def / class / module / block の本体に rescue や ensure があるときも BeginNode(begin_keyword_loc は nil)。",
    "暗黙の BeginNode(begin_keyword_loc が nil)の expression は、Prism では親と同じで `def` / `class` / `do` から始まり、ヘッダ(名前やパラメータ)まで含んでしまう。Steep の変換では、親の本体の region の開始位置から親の終わりまでにする。",
  ],
  "RescueNode" => [
    "複数の rescue 節は subsequent による連鎖(parser は配列だった)。reference は *TargetNode(LocalVariableTargetNode など)。",
    "expression は最後の文で終わる(WhenNode と同じ)。statements.region は次の節のキーワードの直前まで。",
  ],
  "RescueModifierNode" => ["`a rescue b`。parser では rescue ノードの一形態だった。"],
  "ParenthesesNode" => ["parser の括弧つき begin。括弧なしの文の並びは StatementsNode。現状 insert_type_node が括弧つき begin 全体に型アサーションを付けている規則はここに対応する。"],
  "EmbeddedStatementsNode" => ["文字列内の式展開 `#{}`。parser では dstr の中の begin。"],
  "EmbeddedVariableNode" => ["`\"#@x\"` の短縮形。parser では begin(ivar) に展開されていた。"],
  "ParametersNode" => [
    "parser の平坦な args を requireds / optionals / rest / posts / keywords / keyword_rest / block に分けて持つ。TypeInference::BlockParams.from_node などの仕分け処理が不要になり、RBS のメソッド型の構造と揃う。",
  ],
  "MultiWriteNode" => ["parser の masgn + mlhs。lefts / rest / rights の分割は TypeInference::MultipleAssignment が行っている処理そのもの。"],
  "MultiTargetNode" => ["入れ子の `(a, b)`、def / block のパラメータの分割代入(parser の mlhs / procarg0 の分割形)。"],
  "SplatNode" => ["expression が nil のときは匿名 `*`(`*, a = x`、`foo(*)`)。現状の forwarded_restarg は SplatNode(expression: nil)になる。"],
  "ImplicitRestNode" => ["末尾カンマ `a, = x` / `|a,|` / `in [a,]` の暗黙の rest。parser では情報が落ちていた。"],
  "AssocSplatNode" => ["value が nil のときは匿名 `**`(`foo(**)`)。現状の forwarded_kwrestarg はこれになる。"],
  "BlockArgumentNode" => ["expression が nil のときは匿名 `&`。parser の block_pass。CallNode.block に入る。"],
  "KeywordHashNode" => ["括弧なしキーワード引数(parser の kwargs)。括弧つき `foo({a: 1})` は HashNode。"],
  "MatchWriteNode" => ["名前つきキャプチャつき正規表現の `=~`(parser の match_with_lvasgn)。targets に束縛されるローカル変数が明示される。"],
  "SourceEncodingNode" => ["`__ENCODING__`。parser 変換では const Encoding::UTF_8 になり内側の const の location が nil になっていた癖が解消する。型は Encoding。"],
  "SourceFileNode" => ["`__FILE__`。parser 変換では str だった。型は String。"],
  "SourceLineNode" => ["`__LINE__`。parser 変換では int だった。型は Integer。"],
  "ForwardingSuperNode" => ["parser の zsuper。"],
  "ForwardingArgumentsNode" => ["呼び出し側の `...`(parser の forwarded_args)。"],
  "ForwardingParameterNode" => ["定義側の `...`(parser の forward_arg)。"],
  "ConstantPathNode" => ["parser の const(scope あり)。parent が nil のとき `::Foo`(parser の cbase)。"],
  "ConstantReadNode" => ["parser の const(scope なし)。"],
  "ShareableConstantNode" => ["`# shareable_constant_value:` マジックコメント下の定数代入を包む。parser 変換は write をそのまま出していたので、TypeConstruction も write を素通しする。"],
  "ImplicitNode" => ["ハッシュの省略記法 `{x:}` の値や、パターン `{x:}` の値を包む。中身は LocalVariableReadNode か CallNode。"],
  "RangeNode" => ["parser の irange / erange。排他は RangeFlags::EXCLUDE_END。"],
  "WhileNode" => ["parser の while / while_post。`begin ... end while` は LoopFlags::BEGIN_MODIFIER。修飾子形式 `b while a` はフラグなしで end_keyword_loc が nil。"],
  "UntilNode" => ["WhileNode と同じ。"],
  "InNode" => [
  "ガード `in a if cond` は Prism では pattern が IfNode / UnlessNode(statements にパターン)になる。対応する際は要注意。",
  "expression は最後の文で終わる(WhenNode と同じ)。",
],
"StringNode" => ["ヒアドキュメントの expression は開始記号 `<<~EOS` だけ。本文は content_loc(= heredoc_body_loc)、終端記号は closing_loc。"],
"InterpolatedStringNode" => ["ヒアドキュメントの expression は開始記号だけ。本文は parts と heredoc_body_loc、終端記号は closing_loc。現状の Source#find_heredoc_nodes は heredoc_body_loc で書ける。"],
  "HashPatternNode" => ["`Foo(a:, b:)` のような定数つきパターンは constant フィールドで表す(parser の const_pattern)。"],
  "ArrayPatternNode" => ["同上。parser の array_pattern / array_pattern_with_tail / const_pattern(配列)に対応。"],
  "IndexTargetNode" => ["`a[1], b = x` の左辺(parser は value なしの send :[]= だった)。"],
  "CallTargetNode" => ["`a.b, c = x` の左辺(parser は value なしの send :b= だった)。"],
  "DefNode" => ["body は StatementsNode か BeginNode で、常に存在する。メソッドのアノテーション(`@type return` など)は body(または body.statements)の annotations に入る。"],
  "ClassNode" => ["body は常に存在する。`@implements` などは body の annotations に入る。"],
  "ModuleNode" => ["同上。"],
  "SingletonClassNode" => ["parser の sclass。body は常に存在する。"],
  "TypeAssertionNode" => [
    "`expr #: Type`。現状の `(assertion expr <TypeAssertion>)` の置き換え。expression の範囲は式の先頭からコメント末尾まで。",
    "付与規則は Source.insert_type_node のものを移植する: 代入(*WriteNode)は value に付ける、return / break / next、def、KeywordHashNode、WhenNode、AssocNode のキーには付けない、MultiWriteNode は value、ParenthesesNode は全体、attr_* の呼び出しは付けない(inline RBS が扱う)、Data.define / Struct.new の引数には付けない。",
  ],
  "TypeApplicationNode" => [
    "`call #$ Type, Type`。現状の `(tapp sendish <TypeApplication>)` の置き換え。TypeApplication#set_node の逆参照は不要になる。",
    "expression は call の範囲。コメントが call の末尾より後ろにあるときはコメント末尾まで伸ばす。",
  ],
}

STEEP_NODES = [
  {
    "name" => "TypeAssertionNode",
    "fields" => [
      { "name" => "expression", "type" => "node", "kind" => "non-void expression" },
      { "name" => "assertion", "type" => "TypeAssertion" },
    ],
    "comment" => "Represents a type assertion comment attached to an expression.\n    foo #: Integer\n    ^^^^^^^^^^^^^^\n",
  },
  {
    "name" => "TypeApplicationNode",
    "fields" => [
      { "name" => "call", "type" => "node", "kind" => "CallNode" },
      { "name" => "application", "type" => "TypeApplication" },
    ],
    "comment" => "Represents a type application comment attached to a method call.\n    foo.bar(1) #$ Integer\n    ^^^^^^^^^^^^^^^^^^^^^\n",
  },
]

ANNOTATIONS = [
  { "name" => "TypeAssertion", "source" => "#: Type",
    "fields" => [{ "name" => "type", "type" => "RBS::Types::t" }, { "name" => "prefix_loc", "type" => "location" }, { "name" => "type_loc", "type" => "location" }],
    "notes" => ["現状は type_syntax? と type() で 2 回パースし、Locator でさらにパースしている。Source.parse 時に 1 回だけパースして保持する。型名の解決(nesting 依存)は従来通り利用側で行う。"] },
  { "name" => "TypeApplication", "source" => "#$ Type, Type",
    "fields" => [{ "name" => "types", "type" => "Array[RBS::Types::t]" }, { "name" => "prefix_loc", "type" => "location" }] },
  { "name" => "VarTypeAnnotation", "source" => "@type var name: Type",
    "fields" => [{ "name" => "name", "type" => "Symbol" }, { "name" => "type", "type" => "RBS::Types::t" }, { "name" => "keyword_loc", "type" => "location" }, { "name" => "kind_loc", "type" => "location" }, { "name" => "name_loc", "type" => "location" }, { "name" => "colon_loc", "type" => "location" }, { "name" => "type_loc", "type" => "location" }] },
  { "name" => "MethodTypeAnnotation", "source" => "@type method name: MethodType",
    "fields" => [{ "name" => "name", "type" => "Symbol" }, { "name" => "method_type", "type" => "RBS::MethodType" }, { "name" => "keyword_loc", "type" => "location" }, { "name" => "kind_loc", "type" => "location" }, { "name" => "name_loc", "type" => "location" }, { "name" => "colon_loc", "type" => "location" }, { "name" => "type_loc", "type" => "location" }] },
  { "name" => "ConstTypeAnnotation", "source" => "@type const Name: Type",
    "fields" => [{ "name" => "name", "type" => "RBS::TypeName" }, { "name" => "type", "type" => "RBS::Types::t" }, { "name" => "keyword_loc", "type" => "location" }, { "name" => "kind_loc", "type" => "location" }, { "name" => "name_loc", "type" => "location" }, { "name" => "colon_loc", "type" => "location" }, { "name" => "type_loc", "type" => "location" }] },
  { "name" => "IvarTypeAnnotation", "source" => "@type ivar @name: Type",
    "fields" => [{ "name" => "name", "type" => "Symbol" }, { "name" => "type", "type" => "RBS::Types::t" }, { "name" => "keyword_loc", "type" => "location" }, { "name" => "kind_loc", "type" => "location" }, { "name" => "name_loc", "type" => "location" }, { "name" => "colon_loc", "type" => "location" }, { "name" => "type_loc", "type" => "location" }] },
  *%w[return block self instance module break].map { |kind|
    { "name" => "#{kind.capitalize}TypeAnnotation", "source" => "@type #{kind}: Type",
      "fields" => [{ "name" => "type", "type" => "RBS::Types::t" }, { "name" => "keyword_loc", "type" => "location" }, { "name" => "kind_loc", "type" => "location" }, { "name" => "colon_loc", "type" => "location" }, { "name" => "type_loc", "type" => "location" }] }
  },
  { "name" => "ImplementsAnnotation", "source" => "@implements Name[A, B]",
    "fields" => [{ "name" => "name", "type" => "RBS::TypeName" }, { "name" => "type_params", "type" => "Array[Symbol]" }, { "name" => "keyword_loc", "type" => "location" }, { "name" => "name_loc", "type" => "location" }, { "name" => "type_params_loc", "type" => "location?" }] },
  { "name" => "DynamicAnnotation", "source" => "@dynamic name, self.name, self?.name",
    "fields" => [{ "name" => "names", "type" => "Array[DynamicName]" }, { "name" => "keyword_loc", "type" => "location" }],
    "notes" => ["DynamicName は { name: Symbol, kind: :instance | :module | :module_instance, location: RBS::Location }。"] },
]

PARSER_MAPPING = [
  ["send / csend / block / numblock / itblock", "CallNode(block: BlockNode | BlockArgumentNode、`&.` は CallNodeFlags::SAFE_NAVIGATION)。ブロックの引数は BlockNode.parameters(BlockParametersNode | NumberedParametersNode | ItParametersNode)"],
  ["lambda(block の呼び出し側)", "LambdaNode"],
  ["lvasgn / ivasgn / gvasgn / cvasgn / casgn(value あり)", "LocalVariableWriteNode / InstanceVariableWriteNode / GlobalVariableWriteNode / ClassVariableWriteNode / ConstantWriteNode / ConstantPathWriteNode"],
  ["同(value なし: mlhs / for / resbody の対象)", "LocalVariableTargetNode / InstanceVariableTargetNode / GlobalVariableTargetNode / ClassVariableTargetNode / ConstantTargetNode / ConstantPathTargetNode / CallTargetNode / IndexTargetNode"],
  ["op_asgn / or_asgn / and_asgn", "対象の種類ごとの *OperatorWriteNode / *OrWriteNode / *AndWriteNode(LocalVariable / InstanceVariable / GlobalVariable / ClassVariable / Constant / ConstantPath / Call / Index)"],
  ["masgn / mlhs", "MultiWriteNode / MultiTargetNode(lefts / rest / rights)"],
  ["splat(mlhs 内の匿名 `*`)", "SplatNode(expression: nil)。末尾カンマ `a, = x` は ImplicitRestNode"],
  ["begin(括弧なしの文の並び)", "StatementsNode"],
  ["begin(括弧あり)", "ParenthesesNode"],
  ["begin(式展開 `#{}`)", "EmbeddedStatementsNode(`#@x` は EmbeddedVariableNode)"],
  ["kwbegin / rescue / resbody / ensure", "BeginNode(rescue_clause: RescueNode が subsequent で連鎖、else_clause: ElseNode、ensure_clause: EnsureNode)。def / class / block の本体の rescue も BeginNode"],
  ["rescue(修飾子 `a rescue b`)", "RescueModifierNode"],
  ["if(`unless` キーワード)", "UnlessNode"],
  ["if(三項演算子)", "IfNode(if_keyword_loc: nil、then_keyword_loc: `?`、subsequent: ElseNode(else_keyword_loc: `:`))"],
  ["if(`elsif`)", "IfNode.subsequent に入れ子の IfNode"],
  ["while_post / until_post", "WhileNode / UntilNode + LoopFlags::BEGIN_MODIFIER"],
  ["case / when", "CaseNode / WhenNode / ElseNode"],
  ["irange / erange", "RangeNode(+ RangeFlags::EXCLUDE_END)"],
  ["iflipflop / eflipflop", "FlipFlopNode"],
  ["match_current_line", "MatchLastLineNode / InterpolatedMatchLastLineNode"],
  ["args / arg / optarg / restarg / kwarg / kwoptarg / kwrestarg / kwnilarg / blockarg / shadowarg / forward_arg", "ParametersNode(requireds / optionals / rest / posts / keywords / keyword_rest / block)+ RequiredParameterNode / OptionalParameterNode / RestParameterNode / RequiredKeywordParameterNode / OptionalKeywordParameterNode / KeywordRestParameterNode / NoKeywordsParameterNode / BlockParameterNode / ForwardingParameterNode。ブロックは BlockParametersNode(parameters、locals: BlockLocalVariableNode)"],
  ["procarg0", "対応ノード無し。BlockParametersNode の requireds が 1 つだけで他が空のときに自動 splat と判定する。`|(a, b)|` は MultiTargetNode"],
  ["kwargs / pair / kwsplat / block_pass / forwarded_args / forwarded_restarg / forwarded_kwrestarg", "ArgumentsNode の中の KeywordHashNode / AssocNode / AssocSplatNode / BlockArgumentNode(CallNode.block)/ ForwardingArgumentsNode / SplatNode(expression: nil)/ AssocSplatNode(value: nil)"],
  ["zsuper / super / yield", "ForwardingSuperNode / SuperNode / YieldNode"],
  ["defined?", "DefinedNode"],
  ["str / dstr / xstr / sym / dsym / regexp / regopt", "StringNode / InterpolatedStringNode / XStringNode / InterpolatedXStringNode / SymbolNode / InterpolatedSymbolNode / RegularExpressionNode / InterpolatedRegularExpressionNode(regopt は RegularExpressionFlags)"],
  ["const / cbase", "ConstantReadNode / ConstantPathNode(parent が nil で `::Foo`)"],
  ["nth_ref / back_ref", "NumberedReferenceReadNode / BackReferenceReadNode"],
  ["match_with_lvasgn", "MatchWriteNode(call: CallNode、targets: LocalVariableTargetNode の配列)"],
  ["alias / undef", "AliasMethodNode / AliasGlobalVariableNode / UndefNode"],
  ["preexe / postexe", "PreExecutionNode / PostExecutionNode"],
  ["__ENCODING__ / __FILE__ / __LINE__(const / str / int に変換されていた)", "SourceEncodingNode / SourceFileNode / SourceLineNode"],
  ["int / float / rational / complex", "IntegerNode / FloatNode / RationalNode(numerator、denominator)/ ImaginaryNode(numeric)"],
  ["case_match / in_pattern / match_var / match_alt / match_as / match_rest / match_nil_pattern / pin / array_pattern / array_pattern_with_tail / find_pattern / hash_pattern / const_pattern / match_pattern / match_pattern_p / if_guard / unless_guard", "CaseMatchNode / InNode / LocalVariableTargetNode / AlternationPatternNode / CapturePatternNode / SplatNode / NoKeywordsParameterNode / PinnedVariableNode / PinnedExpressionNode / ArrayPatternNode(constant: で定数つき)/ FindPatternNode / HashPatternNode(constant: で定数つき)/ MatchRequiredNode / MatchPredicateNode / ガードは InNode.pattern を包む IfNode / UnlessNode"],
  ["assertion / tapp(Steep が合成していたノード)", "TypeAssertionNode / TypeApplicationNode"],
]

OPEN_QUESTIONS = [
  "名前空間とクラス名(`Steep::AST::Node::IfNode` か `Steep::AST::Ruby::IfNode` か。Prism と同名にして名前空間で区別する案)。",
  "フロントエンド: Prism.parse の結果から直接構築する(推奨。Prism::Compiler のサブクラスで 1 パス)か、当面は parser gem 変換の木から構築するか。前者なら parser gem への依存は型検査から外れ、コメントも Prism::Comment になる。",
    "`unescaped` などフィールド名を Prism のまま使うか、Steep 向きに `value` へ改名するか(ここでは Prism のまま)。",
  "WhenNode / InNode / RescueNode の expression を、本体の region の終わりまで伸ばすか(伸ばすと位置の探索が単純になるが、Prism の範囲と変わる。ここでは伸ばさず、探索側で region を見る)。",
  "ErrorRecoveryNode を落として良いか(LSP で error tolerant にするなら必要)。",
  "アノテーションの型を RBS::Types::t(未解決)で持つか、現状どおり Steep の AST::Types::t で持つか。",
  "`==` / `hash`(TypeEnv の pure node キー)に annotations と location を含めない方針で良いか。",
  "互換プロトコル(parser 風の `type` / `children`)は、木の形が parser と違うので提供しない。TypeConstruction と テストは新 AST に合わせて書き直す前提で良いか。",
]

def transform_field(node_name, field)
  name = field["name"]
  type = field["type"]
  return nil if DROPPED_FIELDS[name] == :all || Array(DROPPED_FIELDS[name]).include?(node_name)

  out = { "name" => name, "type" => type }
  out["kind"] = field["kind"] if field["kind"]

  if ALWAYS_PRESENT_BODIES[node_name]&.include?(name) && type == "node?"
    out["type"] = "node"
    out["steep"] = "Prism では nil 可。Steep では空でも常に存在する(アノテーションの付与先)。"
  end

  out
end

nodes = CONFIG["nodes"].filter_map do |node|
  next if DROPPED_NODES.key?(node["name"])

  out = { "name" => node["name"], "prism" => node["name"] }
  out["steep"] = UNSUPPORTED.include?(node["name"]) ? "unsupported" : "typed"
  out["flags"] = node["flags"] if node["flags"] && KEPT_FLAGS.key?(node["flags"])
  fields = (node["fields"] || []).filter_map { transform_field(node["name"], _1) }
  fields.concat(ADDED_FIELDS.fetch(node["name"], []))
  out["fields"] = fields
  out["comment"] = node["comment"]
  out["steep_notes"] = STEEP_NOTES[node["name"]] if STEEP_NOTES[node["name"]]
  out
end

STEEP_NODES.each do |node|
  out = { "name" => node["name"], "prism" => nil, "steep" => "steep_only", "fields" => node["fields"], "comment" => node["comment"] }
  out["steep_notes"] = STEEP_NOTES[node["name"]] if STEEP_NOTES[node["name"]]
  nodes << out
end

flags = CONFIG["flags"].filter_map do |flag|
  kept = KEPT_FLAGS[flag["name"]] or next
  values = flag["values"].filter_map do |value|
    category = kept[value["name"]] or next
    out = { "name" => value["name"], "category" => category, "comment" => value["comment"].to_s.strip }
    if note = FLAG_NOTES["#{flag["name"]}::#{value["name"]}"]
      out["steep_note"] = note
    end
    out
  end
  { "name" => flag["name"], "values" => values }
end

dropped_flags = CONFIG["flags"].flat_map do |flag|
  flag["values"].filter_map do |value|
    "#{flag["name"]}::#{value["name"]}" unless KEPT_FLAGS.dig(flag["name"], value["name"])
  end
end

header = <<~HEADER
  # Steep AST ノード仕様(ドラフト)
  #
  # このファイルは doc/generate_ast_nodes.rb が生成する。手で編集せず、スクリプト側の差分定義を変更して再生成する。
  #
  #   $ ruby doc/generate_ast_nodes.rb > doc/ast_nodes.yml
  #
  # 方針:
  #   - Steep の AST は Prism のノード構造に従う。nodes の各要素は Prism #{PRISM_SPEC.version} の config.yml の定義を写し、
  #     Steep 向きの差分を適用したもの。フィールドの説明と例は Prism の config.yml を参照する。
  #   - 各ノードは Steep 自身のクラス(Prism のクラスではない)として生成する。`type: location` / `location?` のフィールドは
  #     `<Name>::Location` クラスに束ねられ(フィールド名は `_loc` を外したもの)、`expression`(ノード全体の範囲)が加わる。
  #     各位置は flat な RBS::Location(RBS::Location[bot, bot])。
  #   - 範囲は 2 種類ある。location.expression はノードの範囲で、Prism の範囲をそのまま使う(暗黙の BeginNode だけ調整する)。
#     StatementsNode の location.region と、文字列の heredoc_body は、テキストとして意味のある範囲(本体の領域、ヒアドキュメントの本文)で、
#     expression とは一致しない。アノテーションの付与と、位置からノードを探す処理は region を使う(regions セクション)。
#   - ブロックアノテーションは木の一部にする。本体を表す StatementsNode は空でも常に存在し、`annotations` フィールドを持つ。
  #     型アサーション `#: T` と型適用 `#$ T` は TypeAssertionNode / TypeApplicationNode として木に入る。
  #   - flags は述語メソッド(`safe_navigation?` など)だけを公開し、内部は Integer のビット集合で持つ。Prism の flags のうち、
#     構文の区別(category: syntax)と構文から導ける要約(category: derived)だけを残し、コンパイラ向けのものは落とす。
#   - `==` / `hash` は fields と flags から構造的に計算し、location と annotations は含めない(TypeEnv の pure node キーのため)。
#     flags を含めるのは、`a.b` と `a&.b` のようにフラグだけが違うノードを区別するため。
  #   - 木は Prism.parse の結果から Prism::Compiler のサブクラスで構築する想定(open_questions 参照)。
  #
  # 各ノードのキー:
  #   name / prism:  Steep のクラス名と、対応する Prism のノード名(Steep 独自ノードは prism が null)
  #   steep:         typed = 現状の TypeConstruction で対応する構文を型検査している
  #                  unsupported = 現状 UnsupportedSyntax になる構文
  #                  steep_only = Steep が導入するノード
  #   flags:         Prism の flags 名(flags セクション)。残す値が無いフラグ群(文字列のエンコーディングなど)は付かない
  #   fields:        name / type / kind(Prism と同じ語彙。type_mapping に Ruby 型との対応)。steep キーは Steep での変更点
  #   comment:       Prism の説明(英語)。`^^^` は例の中でそのノードが表す範囲
  #   steep_notes:   Steep 向きの補足(日本語)
HEADER

doc = {
  "version" => "draft-2",
  "prism_version" => PRISM_SPEC.version.to_s,
  "type_mapping" => TYPE_MAPPING,
  "dropped_nodes" => DROPPED_NODES,
  "dropped_fields" => DROPPED_FIELDS.transform_values { _1 == :all ? "all nodes" : _1 },
  "flags" => flags,
"dropped_flags" => {
  "reason" => "コンパイラ向けの情報(エンコーディングの強制、frozen_string_literal、整数リテラルの基数、shareable_constant_value のモード)で、型検査には使わない。必要になった時点で KEPT_FLAGS に足す。",
  "values" => dropped_flags,
},
  "nodes" => nodes,
  "annotations" => ANNOTATIONS,
  "regions" => {
    "description" => "StatementsNode の location.region の定義。開始は「直前のトークンの終わり」、終了は「直後のトークンの始まり」で、文字単位の範囲。空行とコメントを含む。",
    "definitions" => [
      { "node" => "ProgramNode.statements", "start" => "ファイルの先頭", "end" => "ファイルの終わり" },
      { "node" => "DefNode.body", "start" => "rparen_loc、なければ parameters、なければ name_loc の終わり(endless def は equal_loc の終わり)", "end" => "end_keyword_loc の始まり(endless def は本体の終わり)" },
      { "node" => "ClassNode.body", "start" => "superclass、なければ constant_path の終わり", "end" => "end_keyword_loc の始まり" },
      { "node" => "ModuleNode.body", "start" => "constant_path の終わり", "end" => "end_keyword_loc の始まり" },
      { "node" => "SingletonClassNode.body", "start" => "expression の終わり", "end" => "end_keyword_loc の始まり" },
      { "node" => "BlockNode.body", "start" => "BlockParametersNode があればその終わり(`|` を含む)、なければ opening_loc の終わり", "end" => "closing_loc の始まり" },
      { "node" => "LambdaNode.body", "start" => "opening_loc の終わり", "end" => "closing_loc の始まり" },
      { "node" => "(上の body が暗黙の BeginNode のとき)BeginNode.statements", "start" => "上と同じ", "end" => "最初の節(rescue_clause / else_clause / ensure_clause)のキーワードの始まり" },
      { "node" => "BeginNode.statements(`begin` あり)", "start" => "begin_keyword_loc の終わり", "end" => "最初の節のキーワード、なければ end_keyword_loc の始まり" },
      { "node" => "RescueNode.statements", "start" => "then_keyword_loc、なければ reference、なければ最後の exceptions、なければ keyword_loc の終わり", "end" => "次の節(subsequent の rescue / else / ensure)のキーワード、なければ親の end_keyword_loc の始まり" },
      { "node" => "ElseNode.statements", "start" => "else_keyword_loc の終わり", "end" => "end_keyword_loc(`end` / `ensure`)の始まり。三項演算子では ElseNode の終わり" },
      { "node" => "EnsureNode.statements", "start" => "ensure_keyword_loc の終わり", "end" => "end_keyword_loc の始まり" },
      { "node" => "IfNode / UnlessNode.statements", "start" => "then_keyword_loc(三項演算子では `?`)、なければ predicate の終わり。修飾子形式はノードの始まり", "end" => "subsequent / else_clause のキーワード、なければ end_keyword_loc の始まり。修飾子形式は if_keyword_loc の始まり" },
      { "node" => "WhileNode / UntilNode.statements", "start" => "do_keyword_loc、なければ predicate の終わり。修飾子形式と BEGIN_MODIFIER はノードの始まり", "end" => "end_keyword_loc の始まり。修飾子形式と BEGIN_MODIFIER は keyword の始まり" },
      { "node" => "ForNode.statements", "start" => "do_keyword_loc、なければ collection の終わり", "end" => "end_keyword_loc の始まり" },
      { "node" => "WhenNode / InNode.statements", "start" => "then_keyword_loc、なければ最後の条件(InNode は pattern)の終わり", "end" => "次の WhenNode / InNode、else_clause、end_keyword_loc のうち最初のものの始まり" },
      { "node" => "ParenthesesNode / EmbeddedStatementsNode / PreExecutionNode / PostExecutionNode の StatementsNode", "start" => "opening_loc の終わり", "end" => "closing_loc の始まり" },
    ],
    "locator" => [
      "位置からノードを探す処理(Locator、Source#find_nodes)は、子の expression に加えて StatementsNode の region も見る。空行やコメントの上のカーソルでも、どの本体(then 節か else 節か、など)にいるかが分かる。",
      "WhenNode / InNode / RescueNode は expression が最後の文で終わるので、その後ろの空行は親の中で子の expression に入らない。これらの節は statements.region に入っていれば降りる。",
      "ヒアドキュメントの本文の中の位置は、文字列ノードの heredoc_body_loc で判定する(expression は開始記号だけのため)。",
    ],
  },
  "annotation_attachment" => {
    "rule" => "アノテーションのコメントの開始位置を含む region のうち、最も内側のものの StatementsNode.annotations に付ける。",
    "header_rule" => "DefNode / ClassNode / ModuleNode / SingletonClassNode / BlockNode / LambdaNode のヘッダ(キーワードから本体の region の開始まで)にあるコメントは、その本体の StatementsNode に付ける。現状 def のパラメータリストの中に書いたアノテーションは def に付いているため。",
    "notes" => [
      "三項演算子と修飾子形式の本体は、region が文そのものなので、実際にアノテーションが付くことはない。",
      "TypeConstruction は StatementsNode に入るときに annotations を適用する。def / class / block では、そのコンテキスト(メソッドの戻り値型、self の型など)を作るときに使う。",
    ],
    "behavior_changes" => {
      "description" => "現状の行単位の規則(Source#construct_mapping)との違い。Steep 2.1.0 の Source.parse で確認した。いずれも、現状では本来の本体から漏れて外側に付いている。",
      "cases" => [
        { "code" => "case x\nwhen 1 # @type var a: Integer\n  a\nend", "now" => "トップレベル", "new" => "when 節の本体" },
        { "code" => "case x\nwhen 1\n  b\n  a # @type var a: Integer\nend", "now" => "トップレベル(本体の最終行が範囲に入らない)", "new" => "when 節の本体" },
        { "code" => "case x\nwhen 1\n  b\n  # @type var a: Integer\nwhen 2\nend", "now" => "トップレベル", "new" => "when 1 の本体" },
        { "code" => "if x\n  # @type var a: Integer\nend", "now" => "トップレベル(then 節が空だと付与先が無い)", "new" => "then 節の本体" },
        { "code" => "for x in y\n  # @type var a: Integer\n  a\nend", "now" => "トップレベル(for は付与対象外)", "new" => "for の本体" },
        { "code" => "begin\n  a\nrescue\n  b\n  # @type var a: Integer\nensure\n  c\nend", "now" => "begin 全体(parser の ensure ノード)", "new" => "rescue 節の本体" },
        { "code" => "def foo(a, # @type var a: Integer\n        b)\nend", "now" => "def", "new" => "def の本体(header_rule により同じ)" },
      ],
    },
  },
  "parser_mapping" => PARSER_MAPPING.map { |from, to| { "parser" => from, "prism" => to } },
  "open_questions" => OPEN_QUESTIONS,
}

yaml = YAML.dump(doc, line_width: -1).sub(/\A---\n/, "")
puts header
puts
puts yaml
