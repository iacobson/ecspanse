defmodule Ecspanse.Event do
  @moduledoc """
  TODO


  Events are passed to the systems to be processed.
  All systems have access to the events created for the current frame.

  Opts
    - fields: must be a list with all the Event struct keys and their default values (if any)
    Eg: [:foo, :bar, baz: 1]

  The events are cleared at the end of the frame.

  All events need to be defined with `use Ecspanse.Event`.

  A `inserted_at` field with the System time of the creation is added to all events automatically.

  TODO: document the special type of events creted by entity updates, creation and deletion


  Tip: we can find Events in the Systems by their struct like this:
  ```elixir
  Enum.filter(events, &match?(%MyEvent{foo: :bar}, &1)) # this allows further pattern matching in the event struct
  # or
  Enum.filter(events, & &1.__struct__ == MyEvent)
  # or
  Enum.filter(events, & fn %event_module{}  -> event_module == MyEvent end)
  ```
  """

  # TODO: explain why a key is needed.
  # Explain that each frame only one {Module, key} event is accepted. Creating new ones will
  # overwrite the previous one.

  # Special events like Components CRUD are creaded with a random key, to relect all changes
  # of the component in the current frame.

  # in most of the cases, the key may be some user ID, and the user will not be allowed to
  # create more than one of that event per frame.

  @type event_spec ::
          {event_module :: module(), key :: any()}
          | {event_module :: module(), key :: any(), event_fields :: keyword()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :event)

      fields = Keyword.get(opts, :fields, [])

      unless is_list(fields) do
        raise ArgumentError,
              "Invalid fields for Event: #{inspect(__MODULE__)}. The `:fields` option must be a list with all the Event struct keys and their default values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      fields = fields |> Keyword.put(:inserted_at, nil)

      @enforce_keys [:inserted_at]
      defstruct fields

      @doc false
      def __ecs_type__ do
        @ecs_type
      end
    end
  end
end
