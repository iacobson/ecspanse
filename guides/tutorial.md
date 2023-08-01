# Tutorial

The objective of this tutorial is to develop a basic game utilizing the Ecspanse library. The game is the initial stage of an RPG game with minimal features. The implementation focuses on the on the game logic and it does not have a UI. All the user interactions and minimal display will be done via Livebook integration.

## Story

The story of the game is simple:

- the game features a single character (Hero).
- the hero has energy. It starts with 50 energy points and it can have a maximum of 100 energy points. The energy points are used to perform actions. Every 3 seconds the hero restores 1 energy point.
- the hero can move in four directions in a tiles-like manner, without actually implementing a tile system. For example, if the hero moves right it will transition form (0,0) to (1,0) and so on. Each move costs 1 energy point.
- on each move the hero has a chance to find resources: gold, gems, or food. Resources are not inventory items, but tradeable items. The hero can trade resources for inventory items.
- the hero starts with some items in their inventory: 2 energy potions and one leather armor
- the hero can purchase a sword with 5 gold, 3 gems and 4 food.

This setup enables us to delve into fundamental concepts of ECS in general and Ecspanse in particular:

- creating new entities from components
- querying for components
- interacting with the system via events
- scheduling systems to perform actions
- managing entities relationships
- different ways to approach collections of entities or components
- using time-based systems and events

## Spawning the Hero

### Adding the Components

The hero entity will have for now the following components:

```elixir
defmodule Demo.Components.Hero do
  use Ecspanse.Component, state: [name: "Hero"]
end

defmodule Demo.Components.Energy do
  use Ecspanse.Component, state: [current: 50, max: 100]
end

defmodule Demo.Components.Position do
  use Ecspanse.Component, state: [x: 0, y: 0]
end

```

The `Hero` component holds generic information about the hero. The `Energy` holds the current and maximum energy points. The `Position` component holds the current position of the hero as horizontal and vertical coordinates.

Under the hood, the components are structs, with some metadata added by the library.

### The Hero Entity Spec

While this is not mandatory, we extracted the hero entity spec composition in the `Demo.Entities.Hero` module.

```elixir
defmodule Demo.Entities.Hero do
  alias Demo.Components

  @spec new() :: Ecspanse.Entity.entity_spec()
  def new do
    {Ecspanse.Entity,
     components: [
       Components.Hero,
       Components.Energy,
       Components.Position
     ]}
  end
end
```

The `new/0` function does not have any effect. It just prepares the entity spec _(of type `Ecspanse.Entity.entity_spec()`)_ to be spawned.

### The System

The system that spawns the hero is a simple one. It is scheduled to run once, when the game starts.

```elixir
defmodule Demo.Systems.SpawnHero do
  use Ecspanse.System

  @impl true
  def run(_frame) do
    %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Hero.new())
  end
end
```

### Scheduling the System

It is now time schedule the newly created system as a startup system. This is done by updating the `setup/1` function in the `Demo` module. We already created this function in the [Getting Started](./getting_started.md) guide.

```elixir
defmodule Demo do
  use Ecspanse

  alias Demo.Systems

  @impl Ecspanse
  def setup(data) do
    data
    |> Ecspanse.add_startup_system(Systems.SpawnHero)
  end
end
```

If we start the application now, the hero entity will be spawned.

### Querying for the Hero

Next, we will incorporate some helper functions that will prove useful in the next chapters.

```elixir
defmodule Demo.Entities.Hero do
  alias Demo.Components

  #...

  def fetch do
    Ecspanse.Query.select({Ecspanse.Entity}, with: [Components.Hero])
    |> Ecspanse.Query.one()
    |> case do
      {%Ecspanse.Entity{} = entity} -> {:ok, entity}
      _ -> {:error, :not_found}
    end
  end
end
```

In the `Demo.Entities.Hero` module we added the `fetch/0` function. This function uses the `Ecspanse.Query` module to select the hero entity. The `select/2` function is the most flexible way to query for entities and components and it will be used many times in this tutorial. In the current context, the query can be interpreted as:

- select tuples with a single element, Entity -> this queries the `%Ecspanse.Entity{}` struct itself. When we want to return the entity as part of a more complex select query, it needs to be in the first position of the tuple.
- that has the `Demo.Components.Hero` component attached to it.
- return just one record -> this would return the selected entity tuple if found, or otherwise nil. It is important to note that, if many records match the query, it will raise an error. For such cases, the `stream/2` should be used and it will return a stream of results.

We can actually test the function in the `iex` console after starting the server:

```iex
iex(1)> Demo.Entities.Hero.fetch()
{:ok, %Ecspanse.Entity{id: "e950bf44-16d5-46b5-bd21-85aabae50ce8"}}
```

For the other helper function, we will create an API module. Again, this is not part of the library, but it provides an easy way to interact with the game, no matter what front end we will use.

```elixir
defmodule Demo.API do
  @spec fetch_hero_details() :: {:ok, map()} | {:error, :not_found}
  def fetch_hero_details do
    Ecspanse.Query.select(
      {Demo.Components.Hero, Demo.Components.Energy, Demo.Components.Position}
    )
    |> Ecspanse.Query.one()
    |> case do
      {hero, energy, position} ->
        %{name: hero.name, energy: energy.current, max_energy: energy.max, pos_x: position.x, pos_y: position.y}
      _ ->
        {:error, :not_found}
    end
  end
end
```

With this function we want to return a map with the hero details we have implemented so far. This time, the `select/2` function is used to select multiple components. The query can be interpreted as:

- select tuples with three elements, `Demo.Components.Hero`, `Demo.Components.Energy`, `Demo.Components.Position` only from entities that have all three components attached to them.
- return just one record -> this will return a tuple with the three components structs if found, or nil otherwise.

We can test the function in the `iex` console after starting the server:

```iex
iex(2)> Demo.API.fetch_hero_details()
%{name: "Hero", energy: 50, max_energy: 100, pos_x: 0, pos_y: 0}
```
