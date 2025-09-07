defmodule Ecspanse.Template.Event do
  @moduledoc """
  A template event is a generic way of defining the structure for related events that share the same fields.

  The template event guarantees that the event that uses it will have certain fields.
  The event itself can define additional fields, specific to its implementation.

  The framework embeds some predefined event templates:
  - `Ecspanse.Template.Event.Timer` - an event template that is used to create timer events

  ## Options

  See `Ecspanse.Event` for the list of options.

  ## Examples

    ```elixir
      defmodule Demo.Events.ConsumerResource do
        use Ecspanse.Template.Event, fields: [:amount]
      end

      defmodule Demo.Events.ConsumerGold do
        use Demo.Events.ConsumeResource, fields: [:amount, :hero_entity_id]
      end
    ```
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      fields = Keyword.get(opts, :fields, [])

      unless is_list(fields) do
        raise ArgumentError,
              "Invalid fields for Template: #{Kernel.inspect(__MODULE__)}. The `:fields` option must be a list with all the Event struct keys and their default values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      Module.register_attribute(__MODULE__, :template_fields, accumulate: false)
      Module.put_attribute(__MODULE__, :template_fields, fields)

      defmacro __using__(opts) do
        quote bind_quoted: [
                opts: opts,
                template_fields: @template_fields,
                template_module: __MODULE__
              ],
              location: :keep do
          event_fields = Keyword.get(opts, :fields, [])

          unless is_list(event_fields) do
            raise ArgumentError,
                  "Invalid fields for Event: #{Kernel.inspect(__MODULE__)}. The `:fields` option must be a list with all the Event struct keys and their default values (if any). Eg: [:foo, :bar, baz: 1]"
          end

          template_fields_keys =
            Enum.map(template_fields, fn
              {k, _} -> k
              k -> k
            end)

          event_fields_keys =
            Enum.map(event_fields, fn
              {k, _} -> k
              k -> k
            end)

          diff_keys = event_fields_keys -- template_fields_keys

          # merge the template fields with the event fields
          common_fields =
            Enum.map(
              template_fields,
              fn
                {k, v} -> {k, Keyword.get(event_fields, k, v)}
                k -> {k, Keyword.get(event_fields, k)}
              end
            )

          # event specific fields
          event_only_fields =
            Enum.map(diff_keys, fn k -> {k, Keyword.get(event_fields, k)} end)

          fields = common_fields ++ event_only_fields

          use Ecspanse.Event, fields: fields
        end
      end
    end
  end
end
