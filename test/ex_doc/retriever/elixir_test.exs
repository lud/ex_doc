defmodule ExDoc.Retriever.ElixirTest do
  use ExUnit.Case, async: true
  alias ExDoc.ModuleNode
  alias ExDoc.{Retriever, DocAST, DocGroupNode}
  import TestHelper

  @moduletag :tmp_dir

  describe "docs_from_modules/2" do
    test "module", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @moduledoc "Mod docs."
        @moduledoc tags: :public

        @doc "function/0 docs."
        @spec function() :: atom()
        def function(), do: :ok

        @doc "macro/0 docs."
        @spec macro() :: Macro.t()
        defmacro macro(), do: :ok

        def empty_doc_and_specs(), do: :ok

        @doc false
        def doc_false(), do: :ok
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod], %ExDoc.Config{})

      assert %ExDoc.ModuleNode{
               moduledoc_line: 2,
               id: "Mod",
               module: Mod,
               title: "Mod",
               type: :module,
               typespecs: [],
               docs_groups: [functions_group],
               annotations: [:public]
             } = mod

      assert DocAST.to_string(mod.doc) == "<p>Mod docs.</p>"
      assert %DocGroupNode{docs: [empty_doc_and_specs, function, macro]} = functions_group

      assert %ExDoc.DocNode{
               arity: 0,
               annotations: [],
               defaults: [],
               deprecated: nil,
               doc_line: 5,
               group: "Functions",
               id: "function/0",
               name: :function,
               signature: "function()",
               source_url: nil,
               specs: [spec],
               type: :function
             } = function

      assert DocAST.to_string(function.doc) == "<p>function/0 docs.</p>"
      assert Macro.to_string(spec) == "function() :: atom()"

      assert %ExDoc.DocNode{
               arity: 0,
               annotations: ["macro"],
               id: "macro/0",
               signature: "macro()",
               specs: [spec],
               type: :macro
             } = macro

      assert DocAST.to_string(macro.doc) == "<p>macro/0 docs.</p>"
      assert Macro.to_string(spec) == "macro() :: Macro.t()"

      assert %ExDoc.DocNode{
               id: "empty_doc_and_specs/0",
               doc: nil,
               specs: []
             } = empty_doc_and_specs
    end

    test "Elixir functions with defaults", c do
      elixirc(c, ~S"""
      defmodule Mod do
        def foo(a, b \\ nil), do: {a, b}
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod], %ExDoc.Config{})
      [%{docs: [foo]}] = mod.docs_groups

      assert foo.id == "foo/2"
      assert foo.defaults == [foo: 1]
      assert foo.signature == "foo(a, b \\\\ nil)"
    end

    test "macros", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @spec macro(Macro.t) :: Macro.t
        defmacro macro(quoted), do: quoted
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod], %ExDoc.Config{})
      [%{docs: [macro]}] = mod.docs_groups

      assert macro.id == "macro/1"
      assert macro.annotations == ["macro"]
      assert Macro.to_string(macro.specs) == "[macro(Macro.t()) :: Macro.t()]"
    end

    test "callbacks", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @doc "callback1/0 docs."
        @callback callback1() :: :ok

        @callback optional_callback1() :: :ok

        @optional_callbacks optional_callback1: 0

        @macrocallback macrocallback1() :: :ok
      end
      """)

      config = %ExDoc.Config{
        source_url_pattern: fn path, line -> "#{path}:#{line}" end
      }

      {[mod], []} = Retriever.docs_from_modules([Mod], config)
      assert mod.type == :behaviour

      assert [%DocGroupNode{docs: [callback1, macrocallback1, optional_callback1]}] =
               mod.docs_groups

      assert callback1.id == "c:callback1/0"
      assert callback1.signature == "callback1()"
      assert callback1.type == :callback
      assert callback1.annotations == []
      assert callback1.doc_line == 2
      assert callback1.group == "Callbacks"
      assert Path.basename(callback1.source_url) == "nofile:3"
      assert DocAST.to_string(callback1.doc) == "<p>callback1/0 docs.</p>"
      assert Macro.to_string(callback1.specs) == "[callback1() :: :ok]"

      assert optional_callback1.id == "c:optional_callback1/0"
      assert optional_callback1.signature == "optional_callback1()"
      assert optional_callback1.type == :callback
      assert optional_callback1.annotations == ["optional"]
      assert optional_callback1.doc_line == 5
      assert optional_callback1.group == "Callbacks"
      assert Path.basename(optional_callback1.source_url) == "nofile:5"
      refute optional_callback1.doc
      assert Macro.to_string(optional_callback1.specs) == "[optional_callback1() :: :ok]"

      assert macrocallback1.id == "c:macrocallback1/0"
      assert macrocallback1.signature == "macrocallback1()"
      assert macrocallback1.type == :macrocallback
      assert macrocallback1.annotations == []
      assert macrocallback1.doc_line == 9
      assert macrocallback1.group == "Callbacks"
      assert Path.basename(macrocallback1.source_url) == "nofile:9"
      refute macrocallback1.doc
      assert Macro.to_string(macrocallback1.specs) == "[macrocallback1() :: :ok]"

      elixirc(c, ~S"""
      defmodule Impl do
        @behaviour Mod

        def callback1(), do: :ok

        @doc "optional_callback1/0 docs."
        def optional_callback1(), do: :ok

        @doc false
        defmacro macrocallback1(), do: :ok
      end
      """)

      {[impl], []} = Retriever.docs_from_modules([Impl], %ExDoc.Config{})
      assert [%DocGroupNode{docs: [callback1, optional_callback1]}] = impl.docs_groups

      assert callback1.id == "callback1/0"
      assert callback1.type == :function
      assert callback1.annotations == []

      assert callback1.doc |> DocAST.to_string() ==
               ~s|<p>Callback implementation for <code class="inline">c:Mod.callback1/0</code>.</p>|

      assert optional_callback1.id == "optional_callback1/0"
      assert optional_callback1.type == :function
      assert optional_callback1.doc |> DocAST.to_string() == ~s|<p>optional_callback1/0 docs.</p>|
    end

    test "types", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @typedoc "type1/0 docs."
        @type type1() :: atom()

        @typedoc "opaque1/0 docs."
        @opaque opaque1() :: atom()
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod], %ExDoc.Config{})
      [%{docs: [opaque1, type1]}] = mod.docs_groups

      assert type1.id == "t:type1/0"
      assert type1.signature == "type1()"
      assert type1.type == :type
      assert type1.group == "Types"
      assert type1.annotations == []
      assert type1.doc_line == 2
      assert DocAST.to_string(type1.doc) == "<p>type1/0 docs.</p>"
      assert hd(type1.specs) |> Macro.to_string() == "type1() :: atom()"

      assert opaque1.id == "t:opaque1/0"
      assert opaque1.signature == "opaque1()"
      assert opaque1.type == :opaque
      assert opaque1.group == "Types"
      assert opaque1.doc_line == 5
      assert opaque1.doc |> DocAST.to_string() == ~s|<p>opaque1/0 docs.</p>|
      assert hd(opaque1.specs) |> Macro.to_string() == "opaque1()"
    end

    test "protocols", c do
      elixirc(c, ~S"""
      defprotocol Mod do
        def foo(thing)
      end

      defimpl Mod, for: Atom do
        def foo(thing), do: thing
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod, Mod.Atom], %ExDoc.Config{})
      assert mod.type == :protocol

      assert [%{title: "Types", docs: [t]}, %{title: "Functions", docs: [foo]}] = mod.docs_groups

      assert foo.id == "foo/1"
      assert t.id == "t:t/0"
    end

    test "structs", c do
      elixirc(c, ~S"""
      defmodule MyStruct do
        @doc "MyStruct docs."
        defstruct [:field]
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([MyStruct], %ExDoc.Config{})
      [%{docs: [my_struct]}] = mod.docs_groups

      assert my_struct.id == "__struct__/0"
      assert my_struct.annotations == ["struct"]
      assert my_struct.signature == "%MyStruct{}"
    end

    test "exceptions", c do
      elixirc(c, ~S"""
      defmodule MyException do
        defexception [:message]
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([MyException], %ExDoc.Config{})
      assert mod.title == "MyException"
      assert mod.type == :exception

      # TODO: this is because `%ExDoc.Config{}.groups_for_modules == []`
      refute mod.group
    end

    test "defdelegate", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @doc "Doc override."
        defdelegate downcase(str), to: String

        defdelegate upcase(str), to: String
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod], %ExDoc.Config{})
      [%{docs: [downcase, upcase]}] = mod.docs_groups

      assert downcase.id == "downcase/1"
      assert downcase.signature == "downcase(str)"
      assert downcase.specs == []
      assert downcase.doc == ExDoc.Markdown.to_ast("Doc override.")

      assert upcase.id == "upcase/1"
      assert upcase.signature == "upcase(str)"
      assert upcase.specs == []
      assert upcase.doc == ExDoc.Markdown.to_ast("See `String.upcase/1`.")
    end

    test "signatures", c do
      elixirc(c, ~S"""
      defmodule Signatures do
        @callback remote(GenServer.options()) :: :ok
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Signatures], %ExDoc.Config{})
      [%{docs: [remote]}] = mod.docs_groups

      assert remote.signature == "remote(options)"
    end

    test "Mix tasks", c do
      elixirc(c, ~S"""
      defmodule Mix.Tasks.MyTask do
        use Mix.Task

        @doc "The task should win over the callback"
        @callback hello() :: :world

        @impl true
        def run(_), do: :ok
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mix.Tasks.MyTask], %ExDoc.Config{})
      assert mod.title == "mix my_task"
      assert mod.type == :task
      refute mod.group
    end

    test "overlapping defaults", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @doc "Basic example"
        def overlapping_defaults(one, two) when is_list(two),
          do: {one, two}

        @doc "Third default arg overrides previous def clause"
        def overlapping_defaults(one, two, three \\ []),
          do: {one, two, three}

        def two_defaults(one, two) when is_atom(one) and is_atom(two),
          do: {one, two}

        @doc "Two default args"
        def two_defaults(one, two, three \\ [], four \\ [])
            when is_list(one) and is_list(two) and is_list(three) and is_list(four),
            do: {one, two, three, four}

        def special_case(one, two) when is_atom(one) and is_atom(two),
          do: {one, two}

        @doc "This function defines an arity that is less than the one in the previous clause"
        def special_case(one, two \\ [], three \\ [], four \\ [])
            when is_list(one) and is_list(two) and is_list(three) and is_list(four),
            do: {one, two, three, four}

        defmacro in_the_middle(foo, bar) when is_list(foo) and is_list(bar),
          do: quote(do: {unquote(foo), unquote(bar)})

        @doc "default arg is in the middle"
        defmacro in_the_middle(foo, bar \\ Baz, baz),
          do: quote(do: {unquote(foo), unquote(bar), unquote(baz)})
      end
      """)

      {[mod], []} = Retriever.docs_from_modules([Mod], %ExDoc.Config{})

      overlapping_defaults_2 = find_doc(mod, &(&1.id == "overlapping_defaults/2"))
      overlapping_defaults_3 = find_doc(mod, &(&1.id == "overlapping_defaults/3"))
      assert overlapping_defaults_2.defaults == []
      assert overlapping_defaults_3.defaults == []

      two_defaults_2 = find_doc(mod, &(&1.id == "two_defaults/2"))
      two_defaults_4 = find_doc(mod, &(&1.id == "two_defaults/4"))
      assert two_defaults_2.defaults == []
      assert two_defaults_4.defaults == [{:two_defaults, 3}]

      special_case_2 = find_doc(mod, &(&1.id == "special_case/2"))
      special_case_4 = find_doc(mod, &(&1.id == "special_case/4"))
      assert special_case_2.defaults == []
      assert special_case_4.defaults == [special_case: 1, special_case: 3]

      in_the_middle_2 = find_doc(mod, &(&1.id == "in_the_middle/2"))
      in_the_middle_3 = find_doc(mod, &(&1.id == "in_the_middle/3"))
      assert in_the_middle_2.defaults == []
      assert in_the_middle_3.defaults == []
    end

    test "if @moduledoc has the :since attribute, it's applied to everything in the module", c do
      elixirc(c, ~S"""
      defmodule Mod do
        @moduledoc since: "1.0.0"

        @type t() :: :ok

        def function(), do: :ok

        defmacro macro(), do: :ok

        @callback cb() :: :ok
      end
      """)

      assert {[%ExDoc.ModuleNode{} = mod], []} =
               Retriever.docs_from_modules([Mod], %ExDoc.Config{})

      assert %ExDoc.DocNode{annotations: ["since 1.0.0"]} =
               find_doc(mod, &(&1.id == "t:t/0"))

      assert %ExDoc.DocNode{annotations: ["since 1.0.0"]} =
               find_doc(mod, &(&1.id == "c:cb/0"))

      assert %ExDoc.DocNode{annotations: ["since 1.0.0"]} =
               find_doc(mod, &(&1.id == "function/0"))

      assert %ExDoc.DocNode{annotations: ["since 1.0.0", "macro"]} =
               find_doc(mod, &(&1.id == "macro/0"))
    end
  end

  defp find_doc(%ModuleNode{} = mod, predicate) do
    mod.docs_groups
    |> Stream.flat_map(& &1.docs)
    |> Enum.find(predicate)
  end
end
