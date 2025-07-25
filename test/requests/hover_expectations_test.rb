# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  def run_expectations(source)
    position = @__params&.first || { character: 0, line: 0 }

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position },
      )
      server.pop_response.response
    end
  end

  def test_hovering_over_private_constant_from_the_same_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)

        CONST
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 4 } },
      )

      assert_match("CONST", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_on_erb
    source = <<~ERB
      <% String %>
    ERB

    with_server(source, Kernel.URI("file:///fake.erb"), stub_no_typechecker: true) do |server, uri|
      RubyIndexer::RBSIndexer.new(server.global_state.index).index_ruby_core
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 0, character: 4 } },
      )
      response = server.pop_response
      assert_match(/String\b/, response.response.contents.value)
    end
  end

  def test_hovering_for_global_variables
    source = <<~RUBY
      # and write node
      $bar &&= 1
      # operator write node
      $baz += 1
      # or write node
      $qux ||= 1
      # target write node
      $quux, $corge = 1
      # write node
      $foo = 1
      # read node
      $DEBUG
    RUBY

    expectations = [
      { line: 1, documentation: "and write node" },
      { line: 3, documentation: "operator write node" },
      { line: 5, documentation: "or write node" },
      { line: 7, documentation: "target write node" },
      { line: 9, documentation: "write node" },
      { line: 11, documentation: "The debug flag" },
    ]

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      expectations.each do |expectation|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: expectation[:line], character: 1 } },
        )

        assert_match(expectation[:documentation], server.pop_response.response.contents.value)
      end
    end
  end

  def test_hover_apply_target_correction
    source = <<~RUBY
      $bar &&= 1
      $baz += 1
      $qux ||= 1
      $foo = 1
    RUBY

    lines_with_target_correction = [0, 1, 2, 3]

    with_server(source) do |server, uri|
      lines_with_target_correction.each do |line|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: {
            textDocument: { uri: uri },
            position: { line: line, character: 5 },
          },
        )

        assert_nil(server.pop_response.response)
      end
    end
  end

  def test_hovering_precision
    source = <<~RUBY
      module Foo
        module Bar
          class Baz
          end
        end
      end

      Foo::Bar::Baz
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # Foo
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 0 } },
      )
      assert_match(/Foo\b/, server.pop_response.response.contents.value)

      # Foo::Bar
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 5 } },
      )
      assert_match(/Foo::Bar\b/, server.pop_response.response.contents.value)

      # Foo::Bar::Baz
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 10 } },
      )
      assert_match(/Foo::Bar::Baz\b/, server.pop_response.response.contents.value)
    end
  end

  def test_hovering_methods_invoked_on_implicit_self
    source = <<~RUBY
      # typed: false

      class A
        # Hello from `foo`
        def foo; end

        def bar
          foo
        end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      assert_match("Hello from `foo`", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_methods_with_two_definitions
    source = <<~RUBY
      # typed: false

      class A
        # Hello from first `foo`
        def foo; end

        def bar
          foo
        end
      end

      class A
        # Hello from second `foo`
        def foo; end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      response = server.pop_response.response
      assert_match("Hello from first `foo`", response.contents.value)
      assert_match("Hello from second `foo`", response.contents.value)
    end
  end

  def test_hovering_methods_invoked_on_explicit_self
    source = <<~RUBY
      # typed: false

      class A
        # Hello from `foo`
        def foo; end

        def bar
          self.foo
        end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 9, line: 7 } },
      )

      assert_match("Hello from `foo`", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_over_private_constant_from_different_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)
      end

      A::CONST # invalid private reference
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 5 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hovering_over_gemfile_dependency_name
    source = <<~RUBY
      gem 'rake'
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 0 } },
      )

      response = server.pop_response.response
      spec = Gem.loaded_specs["rake"]

      assert_includes(response.contents.value, spec.name)
      assert_includes(response.contents.value, spec.version.to_s)
      assert_includes(response.contents.value, spec.homepage)
    end
  end

  def test_hovering_over_gemfile_dependency_triggers_only_for_first_arg
    source = <<~RUBY
      gem 'rake', '~> 1.0'
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 13, line: 0 } },
      )

      response = server.pop_response.response

      assert_nil(response)
    end
  end

  def test_hovering_over_gemfile_dependency_with_missing_argument
    source = <<~RUBY
      gem()
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hovering_over_gemfile_dependency_with_non_gem_argument
    source = <<~RUBY
      gem(method_call)
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_addons
    source = <<~RUBY
      # Hello
      class Post
      end

      Post
    RUBY

    begin
      create_hover_addon

      with_server(source, stub_no_typechecker: true) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { character: 0, line: 4 } },
        )

        assert_match(<<~RESPONSE.strip, server.pop_response.response.contents.value)
          Title

          **Definitions**: [fake.rb](file:///fake.rb#L2,1-3,4)
          Links



          Hello
          Documentation from middleware: Post
        RESPONSE
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
    end
  end

  def test_hover_precision_for_methods_with_block_arguments
    source = <<~RUBY
      class Foo
        # Hello
        def foo(&block); end

        def bar
          foo(&:argument)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 12, line: 5 } },
      )
      # Hover on `argument` should not show you the `foo` documentation
      assert_nil(server.pop_response.response)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)
    end
  end

  def test_hover_instance_variables
    source = <<~RUBY
      class Foo
        def initialize
          # Hello
          @a = 1
        end

        def bar
          @a
        end

        def baz
          @a = 5
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_for_class_variables
    source = <<~RUBY
      class Foo
        def foo
          # or write node
          @@a ||= 1
        end

        def bar
          # operator write node
          @@a += 5
        end

        def baz
          @@a
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 12 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("or write node", contents)
      assert_match("operator write node", contents)
    end
  end

  def test_hovering_for_inherited_class_variables
    source = <<~RUBY
      module Foo
        def set_variable
          # Foo
          @@bar = 1
        end
      end

      class Parent
        def set_variable
          # Parent
          @@bar = 5
        end
      end

      class Child < Parent
        include Foo

        def do_something
          @@bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 18 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)
      assert_match("Parent", contents)
    end
  end

  def test_hovering_for_class_variables_in_different_context
    source = <<~RUBY
      class Foo
        # comment 1
        @@a = 1

        class << self
          # comment 2
          @@a = 2

          def foo
            # comment 3
            @@a = 3
          end
        end

        def bar
          # comment 4
          @@a = 4
        end

        def self.baz
          # comment 5
          @@a = 5
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 2 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("comment 1", contents)
      assert_match("comment 2", contents)
      assert_match("comment 3", contents)
      assert_match("comment 4", contents)
      assert_match("comment 5", contents)
    end
  end

  def test_hovering_over_inherited_methods
    source = <<~RUBY
      module Foo
        module First
          # Method 1
          def method1; end
        end

        class Bar
          # Method 2
          def method2; end
        end

        class Baz < Bar
          include First

          def method3
            method1
            method2
          end
        end
      end
    RUBY

    # Going to definition on `argument` should not take you to the `foo` method definition
    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 15 } },
      )
      assert_match("Method 1", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 16 } },
      )
      assert_match("Method 2", server.pop_response.response.contents.value)
    end
  end

  def test_hover_for_inherited_instance_variables
    source = <<~RUBY
      module Foo
        def set_ivar
          # Foo
          @a = 1
        end
      end

      class Parent
        def initialize
          # Parent
          @a = 5
        end
      end

      class Child < Parent
        include Foo

        def do_something
          @a
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 18 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)
      assert_match("Parent", contents)
    end
  end

  def test_hover_for_methods_shows_parameters
    source = <<~RUBY
      class Foo
        def bar(a, b = 1, *c, d:, e: 1, **f, &g)
        end

        def baz
          bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("bar(a, b = <default>, *c, d:, e: <default>, **f, &g)", contents)
    end
  end

  def test_hover_for_methods_shows_overload_count
    source = <<~RUBY
      String.try_convert
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 8, line: 0 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("try_convert(object)", contents)
      assert_match("(+2 overloads)", contents)
    end
  end

  def test_hover_for_singleton_methods
    source = <<~RUBY
      class Foo
        # bar
        def self.bar
        end

        class << self
          # baz
          def baz; end
        end
      end

      Foo.bar
      Foo.baz
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("bar", contents)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 12 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("baz", contents)
    end
  end

  def test_definition_for_class_instance_variables
    source = <<~RUBY
      class Foo
        # Hey!
        @a = 123

        def self.bar
          @a
        end

        class << self
          def baz
            @a
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Hey!", contents)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 10 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Hey!", contents)
    end
  end

  def test_hover_for_aliased_methods
    source = <<~RUBY
      class Parent
        # Original
        def bar; end
      end

      class Child < Parent
        # Alias
        alias baz bar

        def do_something
          baz
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 10 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Alias", contents)
      assert_match("Original", contents)
    end
  end

  def test_hover_for_super_calls
    source = <<~RUBY
      class Parent
        # Foo
        def foo; end
        # Bar
        def bar; end
      end

      class Child < Parent
        def foo(a)
          super()
        end

        def bar
          super
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 9 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 13 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Bar", contents)
    end
  end

  def test_hover_is_disabled_for_self_methods_on_typed_true
    source = <<~RUBY
      # typed: true
      class Child
        def foo
          bar
        end

        # Hey!
        def bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 3 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_is_disabled_for_instance_variables_on_typed_strict
    source = <<~RUBY
      # typed: strict
      class Child
        def initialize
          # Hello
          @something = 123 #: Integer
        end

        def bar
          @something
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 8 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_is_disabled_on_super_for_typed_true
    source = <<~RUBY
      # typed: true
      class Parent
        def foo; end
      end
      class Child < Parent
        def foo
          super
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 6 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_for_guessed_receivers
    source = <<~RUBY
      class User
        def name; end
      end

      user.name
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 4 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Guessed receiver: User", contents)
      assert_match("Learn more about guessed types", contents)
    end
  end

  def test_hover_for_keywords
    test_cases = {
      "yield" => {
        source: <<~RUBY,
          def foo
            yield
          end
        RUBY
        position: { line: 1, character: 2 },
      },
      "break" => {
        source: <<~RUBY,
          while true
            break
          end
        RUBY
        position: { line: 1, character: 2 },
      },
    }

    test_cases.each do |keyword, config|
      with_server(config[:source]) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: {
            textDocument: { uri: uri },
            position: config[:position],
          },
        )

        contents = server.pop_response.response.contents.value
        assert_match("```ruby\n#{keyword}\n```", contents)
        assert_match(
          RubyLsp::KEYWORD_DOCS[keyword] || "No documentation found for #{keyword}",
          contents,
        )
        assert_match("[Read more](#{RubyLsp::STATIC_DOCS_PATH}/#{keyword}.md)", contents)
      end
    end
  end

  def test_hover_call_node_precision
    source = <<~RUBY
      class Foo
        def message
          "hello!"
        end
      end

      class Bar
        def with_foo(foo)
          @foo_message = foo.message
        end
      end
    RUBY

    with_server(source) do |server, uri|
      # On the `foo` receiver, we should not show any results
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 19, line: 8 } },
      )
      assert_nil(server.pop_response.response)

      # On `message`, we should
      server.process_message(
        id: 2,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 23, line: 8 } },
      )
      refute_nil(server.pop_response.response)
    end
  end

  def test_hovering_constants_shows_complete_name
    source = <<~RUBY
      # typed: ignore
      module Foo
        CONST = 123

        module Bar
          class Baz; end

          Baz
        end
      end

      QUX = 42
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )
      assert_match("```ruby\nFoo::Bar::Baz\n```", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 2 } },
      )
      assert_match("```ruby\nFoo::CONST\n```", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 11 } },
      )
      assert_match("```ruby\nQUX\n```", server.pop_response.response.contents.value)
    end
  end

  private

  def create_hover_addon
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def name
        "HoverAddon"
      end

      def deactivate; end

      def version
        "0.1.0"
      end

      def create_hover_listener(response_builder, nesting, dispatcher)
        klass = Class.new do
          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            @response_builder.push(
              "Documentation from middleware: #{node.slice}", category: :documentation
            )
            @response_builder.push(
              "Links", category: :links
            )
            @response_builder.push(
              "Title", category: :title
            )
          end
        end

        klass.new(response_builder, dispatcher)
      end
    end
  end
end
