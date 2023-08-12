# Ecspanse

## About

- no persistance at the moment

## To Do

- improve docs
- more tests outside the happy path

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ecspanse` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecspanse, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ecspanse](https://hexdocs.pm/ecspanse).

# Testing

TODO
The Ecspanse.Server is not automatically starting in the test environment.
This allows testing different system configurations in isolation.
But if the tests needs to run with the actual game behaviour, the server can be manually started in the test:

```elixir
defmodule MyGame do
  use Ecspanse

  def setup(data) do
    data
    |> Ecspanse.Server.add_system(TestSystem1)
    |> Ecspanse.Server.add_system(TestSystem2)
  end
end

# In the test file

setup do
  start_supervised({MyGame, :test})
end
```

**Important** When starting the test server, the `:test` atom must be provided as value in the `start_supervised` function. Otherwise the Ecspanse.Server will not start.
Example: `start_supervised({MyGame, :test})`
