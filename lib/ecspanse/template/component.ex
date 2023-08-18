defmodule Ecspanse.Template.Component do
  @moduledoc """
  A template component is a generic way of defining the structure for related components.
  They share the same state fields and tags.

  The template component, coupled with tags allow a flexible way to manage collections of related components.
  See `Ecspanse.Component` for more details.

  The template component guarantees that the component that uses it will have certain fields in its state and certain tags.
  The component itself can define additional fields or tags, specific to its implementation.
  It can also override the initial values of the template fields.

  The framework embeds some predefined component templates:
  - `Ecspanse.Template.Component.Timer` - a component template that is used to create timer components.

  ## Options

  See `Ecspanse.Component` for the list of options.

  ## Examples

    ```elixir
      defmodule Demo.Componenets.Resource do
        use Ecspanse.Template.Component, state: [amount: 0], tags: [:resource]
      end

      defmodule Demo.Componenets.Gold do
        use Demo.Components.Resource, state: [amount: 5, exchange_rate: 2], tags: [:available]
      end
    ```
  """

  @doc """
  **Optional** callback to validate the template and component state fields.

  It runs only at compile time, and it takes the list of fields as the only argument and returns `:ok` or an error tuple.


  > #### Info  {: .error}
  > When an error tuple is returned, it raises an exception with the provided error message.

  For runtime component state validation see `c:Ecspanse.Component.validate/1`.

  ## Examples

    ```elixir
    defmodule Demo.Components.Resources do
      use Ecspanse.Template.Component, state: [amount: 0]

      def validate(state_fields) do
        amount = Keyword.get(state_fields, :amount, 0)
        if is_integer(amount) and amount >= 0 do
          :ok
        else
          {:error, "Invalid amount value"}
        end
      end
    end
    ```
  """
  @callback validate(state :: keyword()) :: :ok | {:error, any()}
  @optional_callbacks validate: 1

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ecspanse.Template.Component

      tags = Keyword.get(opts, :tags, [])

      unless is_list(tags) do
        raise ArgumentError,
              "Invalid tags for Template: #{inspect(__MODULE__)}. The `:tags` option must be a list of atoms."
      end

      state = Keyword.get(opts, :state, [])

      unless is_list(state) do
        raise ArgumentError,
              "Invalid state for Template: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Component state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      Module.register_attribute(__MODULE__, :template_tags, accumulate: false)
      Module.register_attribute(__MODULE__, :template_state, accumulate: false)
      Module.put_attribute(__MODULE__, :template_tags, tags)
      Module.put_attribute(__MODULE__, :template_state, state)

      # nested macro. This is the one used by the actual component
      defmacro __using__(opts) do
        quote bind_quoted: [
                opts: opts,
                template_tags: @template_tags,
                template_state: @template_state,
                template_module: __MODULE__
              ],
              location: :keep do
          component_tags = Keyword.get(opts, :tags, [])

          unless is_list(component_tags) do
            raise ArgumentError,
                  "Invalid tags for Component: #{inspect(__MODULE__)}. The `:tags` option must be a list of atoms."
          end

          component_state = Keyword.get(opts, :state, [])

          unless is_list(component_state) do
            raise ArgumentError,
                  "Invalid state for Component: #{inspect(__MODULE__)}. The `:state` option must be a list with all the Component state struct keys and their initial values (if any). Eg: [:foo, :bar, baz: 1]"
          end

          tags = Enum.uniq(template_tags ++ component_tags)

          template_state_keys =
            Enum.map(template_state, fn
              {k, _} -> k
              k -> k
            end)

          component_state_keys =
            Enum.map(component_state, fn
              {k, _} -> k
              k -> k
            end)

          diff_keys = component_state_keys -- template_state_keys

          # merge the template state with the component state
          common_state =
            Enum.map(
              template_state,
              fn
                {k, v} -> {k, Keyword.get(component_state, k, v)}
                k -> {k, Keyword.get(component_state, k)}
              end
            )

          # component specific fields
          component_only_state =
            Enum.map(diff_keys, fn k -> {k, Keyword.get(component_state, k)} end)

          state = common_state ++ component_only_state

          if function_exported?(template_module, :validate, 1) do
            case template_module.validate(state) do
              :ok ->
                :ok

              {:error, error} ->
                raise ArgumentError, error
            end
          else
            :ok
          end

          use Ecspanse.Component, state: state, tags: tags
        end
      end
    end
  end
end
