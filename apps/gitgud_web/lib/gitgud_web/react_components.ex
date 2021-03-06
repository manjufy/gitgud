defmodule GitGud.Web.ReactComponents do
  @moduledoc """
  Functions to make rendering React components.
  """

  import Phoenix.HTML.Tag

  @doc """
  Generates a div containing the named React component with no props or attrs.

  Returns safe html: `{:safe, [60, "div", ...]}`.
  You can utilize this in your Phoenix views:
  ```
  <%= GitGud.Web.React.react_component("MyComponent") %>
  ```
  The resulting `<div>` tag is formatted specifically for the included javascript
  helper to then turn into your named React component.
  """
  def react_component(name), do: react_component(name, %{})

  @doc """
  Generates a div containing the named React component with the given `props`.

  Returns safe html: `{:safe, [60, "div", ...]}`.
  Props can be passed in as a Map or a List.
  You can utilize this in your Phoenix views:
  ```
  <%= GitGud.Web.React.react_component("MyComponent", %{language: "elixir", awesome: true}) %>
  ```
  The resulting `<div>` tag is formatted specifically for the included javascript
  helper to then turn into your named React component and then pass in the `props` specified.
  """
  def react_component(name, props) when is_list(props), do: react_component(name, Enum.into(props, %{}))
  def react_component(name, props) when is_map(props) do
    props = Poison.encode!(props)
    content_tag(:div, "", [{:data, [react_class: name, react_props: props]}])
  end

  @doc """
  Generates a div containing the named React component with the given `props` and `attrs`.

  Returns safe html: `{:safe, [60, "div", ...]}`.

  You can utilize this in your Phoenix views:
  ```
  <%= GitGud.Web.React.react_component(
        "MyComponent",
        %{language: "elixir", awesome: true},
        class: "my-component"
      ) %>
  ```
  The resulting `<div>` tag is formatted specifically for the included javascript
  helper to then turn into your named React component and then pass in the `props` specified.
  """
  def react_component(name, props, attrs) when is_list(props), do: react_component(name, Enum.into(props, %{}), attrs)
  def react_component(name, props, attrs) when is_map(props) do
    props = Poison.encode!(props)
    react_attrs = [react_class: name, react_props: props]
    content_tag(:div, "", attrs ++ [{:data, react_attrs}])
  end
end
