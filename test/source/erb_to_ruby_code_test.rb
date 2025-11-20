require_relative "../test_helper"

class Steep::Source::ErbToRubyCodeTest < Minitest::Test
  include TestHelper

  def test_erb_output_tag_to_ruby_code
    erb_source_code    = "<%= if order.with_error? %>"
    expected_ruby_code = "    if order.with_error?  ;"

    ruby_code = Steep::Source::ErbToRubyCode.convert(erb_source_code)

    assert_equal expected_ruby_code, ruby_code
  end

  def test_erb_output_tag_without_begin_space_to_ruby_code
    erb_source_code    = "<%=if order.with_error? %>"
    expected_ruby_code = "   if order.with_error?  ;"

    ruby_code = Steep::Source::ErbToRubyCode.convert(erb_source_code)

    assert_equal expected_ruby_code, ruby_code
  end

  def test_erb_output_tag_without_end_space_to_ruby_code
    erb_source_code    = "<%=if order.with_error?%>"
    expected_ruby_code = "   if order.with_error? ;"

    ruby_code = Steep::Source::ErbToRubyCode.convert(erb_source_code)

    assert_equal expected_ruby_code, ruby_code
  end

  def test_erb_execution_tag_to_ruby_code
    erb_source_code    = "<div> Count <% 1 + '2' %> </div>"
    expected_ruby_code = "               1 + '2'  ;       "

    ruby_code = Steep::Source::ErbToRubyCode.convert(erb_source_code)

    assert_equal expected_ruby_code, ruby_code
  end

  def test_erb_to_ruby_code_handles_comments_html_and_multiple_tags
    form_erb = <<ERB
<% # This is a comment %>
<div class="container">
  <%= user.name %>
  <% if user.admin? %>
    <%= link_to "Admin Panel", admin_path %>
  <% end %>
  <p>Welcome!</p>
</div>
ERB

    ruby_result = Steep::Source::ErbToRubyCode.convert(form_erb)

    expected_ruby_result = <<RUBY
   # This is a comment   
                       
      user.name  ;
     if user.admin?  ;
        link_to "Admin Panel", admin_path  ;
     end  ;
                 
      
RUBY

    assert_equal expected_ruby_result, ruby_result
  end

  def test_erb_multiline_tag_with_closing_on_separate_line
    erb_source_code = <<ERB
<%= form_with model: @user,
              url: users_path,
              local: true
            %>
ERB

    expected_ruby_code = <<RUBY
    form_with model: @user,
              url: users_path,
              local: true              ;
RUBY

    ruby_code = Steep::Source::ErbToRubyCode.convert(erb_source_code)

    assert_equal expected_ruby_code, ruby_code
  end

  def test_erb_multiple_tags_same_line_conversion 
    erb_with_two_tags_ruby = <<ERB
<div class="alert">
  <strong><%= t("messages.welcome") %></strong> <%= current_user.name %>
</div>
<%= link_to "Home", root_path %>
ERB

    expected_ruby_with_two_tags = <<RUBY
                   
              t("messages.welcome")  ;              current_user.name  ;
      
    link_to "Home", root_path  ;
RUBY

    assert_equal expected_ruby_with_two_tags, Steep::Source::ErbToRubyCode.convert(erb_with_two_tags_ruby)
  end

  def test_erb_with_dash_to_ruby_code
    erb_source_code    = "<%- if foo -%>"
    expected_ruby_code = "    if foo   ;"

    ruby_code = Steep::Source::ErbToRubyCode.convert(erb_source_code)

    assert_equal expected_ruby_code, ruby_code
  end
end
