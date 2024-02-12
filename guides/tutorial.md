# Tutorial

The objective of this tutorial is to develop a basic game utilizing the Ecspanse framework. The game is the initial stage of an RPG game with minimal features. The implementation focuses on the on the game logic and it does not have a UI. All the user interactions and minimal display will be done via Livebook integration.

## Story

The story of the game is simple:

- the game features a single character (Hero).
- the hero has energy. It starts with 50 energy points and it can have a maximum of 100 energy points. The energy points are used to perform actions. Every 3 seconds the hero restores 1 energy point.
- the hero can move in four directions in a tiles-like manner, without actually implementing a tile system. For example, if the hero moves right it will transition from (0,0) to (1,0) and so on. Each move costs 1 energy point.
- on each move the hero has a chance to find resources: gold or gems. Resources are not inventory items, but tradeable items. The hero can trade resources for inventory items.
- the hero starts with some items in their inventory: 2 potions and one pair of boots.
- the hero can purchase a map with 2 gold and a compass with 3 gold and 2 gems.

This setup enables us to delve into fundamental concepts of ECS in general and Ecspanse in particular:

- creating new entities from components
- querying for components
- interacting with the system via events
- scheduling systems to perform actions
- managing entities relationships
- different ways to approach collections of entities or components
- using time-based systems and events

---

## Spawning the Hero

The goal of this chapter is to spawn the hero entity with its components on game startup.

> ### Ecspanse Concepts 1 {: .info}
>
> - creating components
> - using commands to spawn entities
> - creating and scheduling systems
> - querying components

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

The following options are available when defining a component:

- `:state` - the fields and the initial state of the component. It should be a list or a keyword list.
- `:tags` - a list of atoms that can be used to tag the component. Tags are an alternate way of querying components.

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

The `new/0` function does not have any effect. It just prepares the entity spec _(of type `t:Ecspanse.Entity.entity_spec/0`)_ to be spawned.

### The Spawn Hero System

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

The system must implement the `c:Ecspanse.System.WithoutEventSubscriptions.run/1` or `c:Ecspanse.System.WithEventSubscriptions.run/2` callback. In this case, it is a generic system, not subscribing to any events, so we will use `run/1`. The callback receives the `t:Ecspanse.Frame.t/0` as argument.

Operations that involve the creation of entities or components are done via the functions in the `Ecspanse.Command` module. The commands cannot be executed outside of a system.

### Scheduling the Spawn Hero System

It is now time to schedule the newly created system as a startup system. This is done by updating the `c:Ecspanse.setup/1` function in the `Demo` module. We already created this function in the [Getting Started](./getting_started.md) guide.

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

In the `Demo.Entities.Hero` module we added the `fetch/0` function. This function uses the `Ecspanse.Query` module to select the hero entity. The `Ecspanse.Query.select/2` function is the most flexible way to query for entities and components and it will be used many times in this tutorial. In the current context, the query can be interpreted as:

- select tuples with a single element, Entity -> this queries the `%Ecspanse.Entity{}` struct itself. When we want to return the entity as part of a more complex select query, it needs to be in the first position of the tuple.
- that has the `Demo.Components.Hero` component attached to it.
- return just one record -> this would return the selected entity tuple if found, or otherwise nil. It is important to note that, if many records match the query, it will raise an error. For such cases, the `Ecspanse.Query.stream/1` should be used and it will return a stream of results.

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
      {Ecspanse.Entity, Demo.Components.Hero, Demo.Components.Energy, Demo.Components.Position}
    )
    |> Ecspanse.Query.one()
    |> case do
      {hero_entity, hero, energy, position} ->
        {:ok, %{name: hero.name, energy: energy.current, max_energy: energy.max, pos_x: position.x, pos_y: position.y}}
      _ ->
        {:error, :not_found}
    end
  end
end
```

This function, returns a map with the hero details we have implemented so far. This time, the `select/2` function is used to select multiple components. The query can be interpreted as:

- select tuples with three elements, `Demo.Components.Hero`, `Demo.Components.Energy`, `Demo.Components.Position` only from entities that have all three components attached to them.
- return just one record -> this will return a tuple with the three components structs if found, or nil otherwise.

We can test the function in the `iex` console after starting the server:

```iex
iex(2)> Demo.API.fetch_hero_details()
%{name: "Hero", energy: 50, max_energy: 100, pos_x: 0, pos_y: 0}
```

---

## Hero Movement

The goal of this chapter is to implement the hero movement. The hero will be able to move in the four directions: up, down, left and right.

> ### Ecspanse Concepts 2 {: .info}
>
> - receiving external input through events
> - implementing and scheduling async systems
> - locking components for parallel operations
> - implementing systems that subscribe to events
> - updating components with commands

### The Move Event

Ecspanse receives external input through events. Let's implement the move event.

```elixir
defmodule Demo.Events.MoveHero do
  use Ecspanse.Event, fields: [:direction]
end
```

Similar to the components, the events are structs under the hood. The fields and their default values are defined with the `:fields` option.

We can also expose the event in the API module:

```elixir
defmodule Demo.API do
  #...
  @spec move_hero(direction :: :up | :down | :left | :right) :: :ok
  def move_hero(direction) do
    Ecspanse.event({Demo.Events.MoveHero, direction: direction})
  end
end
```

We create another event that will be emitted when the hero actually moved to handle various side effects.

```elixir
defmodule Demo.Events.HeroMoved do
  use Ecspanse.Event
end
```

### The Move System

The role of the move system is to listen to move events, then check if the hero has enough energy to move and if so, update the hero position and adjust the energy. We want this system to run asynchronously.

```elixir
defmodule Demo.Systems.MoveHero do
  use Ecspanse.System,
    lock_components: [Demo.Components.Position, Demo.Components.Energy],
    event_subscriptions: [Demo.Events.MoveHero]

  alias Demo.Components

  @impl true
  def run(%Demo.Events.MoveHero{direction: direction}, _frame) do
    components =
      Ecspanse.Query.select({Components.Position, Components.Energy}, with: [Components.Hero])
      |> Ecspanse.Query.one()

    with {position, energy} <- components,
         :ok <- validate_enough_energy_to_move(energy) do
      Ecspanse.Command.update_components!([
        {energy, current: energy.current - 1},
        {position, update_coordinates(position, direction)}
      ])
      Ecspanse.event(Demo.Events.HeroMoved)
    end
  end

  defp validate_enough_energy_to_move(%Components.Energy{current: current_energy}) do
    if current_energy >= 1 do
      :ok
    else
      {:error, :not_enough_energy}
    end
  end

  defp update_coordinates(%Components.Position{x: x, y: y}, direction) do
    case direction do
      :up -> [x: x, y: y + 1]
      :down -> [x: x, y: y - 1]
      :left -> [x: x - 1, y: y]
      :right -> [x: x + 1, y: y]
      _ -> [x: x, y: y]
    end
  end
end
```

#### Component Locking

We said that the move system will run asynchronously. This means that it will run in parallel with the other systems. The `lock_components` option is used to specify the components that will be locked by the system. That means that no other systems that lock at least one of the locked components will run in the same parallel batch as the `MoveHero` system. In our case, we want to lock the `Demo.Components.Position` and `Demo.Components.Energy` components. This is because we want to update the hero position and energy, and we need to avoid race conditions.

The commands will check if the system is async and will raise an error if we try to update, insert or delete components that are not locked. For extra safety we can also lock components for which we don't update the state, but we read and depend on it.

#### Event Subscriptions

Not all systems are required to run every single frame. The `MoveHero` system is useful only when a `MoveHero` event is received. The `event_subscriptions` option is used to specify the events that the system is interested in. The system will run only when at least one of the subscribed events is received.

The systems that have events subscriptions need to implement the `run/2` callback. The first argument is the event that triggered the system. The second argument is the current frame.

#### Updating the Components

It is a good practice to make sure that actions can be performed before committing any updates. Reverting the changes would be more difficult and inefficient.

In our case, we want to make sure that the hero has enough energy before updating the `Energy` and `Position` components state.

### Scheduling the Move System

We use `add_system/2` to schedule the `MoveHero` system to run asynchronously.

```elixir
defmodule Demo do
  #...
  def setup(data) do
    data
    #...
    |> Ecspanse.add_system(Systems.MoveHero)
  end
end
```

We can try the hero movement in the `iex` console:

```iex
iex(1)> Demo.API.fetch_hero_details()
%{name: "Hero", energy: 50, max_energy: 100, pos_x: 0, pos_y: 0}
iex(2)> Demo.API.move_hero(:up)
:ok
iex(3)> Demo.API.move_hero(:right)
:ok
iex(4)> Demo.API.fetch_hero_details()
%{name: "Hero", energy: 48, max_energy: 100, pos_x: 1, pos_y: 1}
```

---

## Energy Regeneration

The goal of this chapter is to implement the energy regeneration. The hero will restore 1 point of energy every 3 seconds.

> ### Ecspanse Concepts 3 {: .info}
>
> - using the timer to schedule events at precise intervals
> - using built-in component and event templates
> - ordering async systems
> - conditionally running systems
> - new ways of querying entities and components

### The Energy Timer Component

Timer-based components use the provided `Ecspanse.Template.Component.Timer` component template. The timer component is a special component that is used to schedule events at precise intervals. The timer component template exposes the following fields:

- `:duration` - the countdown duration in milliseconds
- `:time` - the current countdown time in milliseconds
- `:event` - the event that will be triggered when the countdown reaches 0
- `:mode` - `:repeat | :once | :temporary` - decides the timer behavior after the countdown reaches 0.
- `:paused` - `boolean` - can be used to pause the timer

We will discuss more about template components in the next chapter.

```elixir
defmodule Demo.Components.EnergyTimer do
  use Ecspanse.Template.Component.Timer,
    state: [duration: 3000, time: 3000, event: Demo.Events.EnergyTimerFinished, mode: :repeat]
end
```

We add the new component to the Hero entity:

```elixir
defmodule Demo.Entities.Hero do
  #...
  @spec new() :: Ecspanse.Entity.entity_spec()
  def new do
    {Ecspanse.Entity,
    components: [
      Components.Hero,
      Components.Energy,
      Components.Position,
      Components.EnergyTimer
    ]}
  end
  #...
end
```

### The Energy Timer Finished Event

Timer-based events use the provided `Ecspanse.Template.Event.Timer` event template. The timer event template exposes the following fields:

- `entity_id` - the id of the entity that owns the timer component

```elixir
defmodule Demo.Events.EnergyTimerFinished do
  use Ecspanse.Template.Event.Timer
end
```

This event will be automatically triggered when the EnergyTimer component duration reaches 0.

### The Energy Restore System

```elixir
defmodule Demo.Systems.RestoreEnergy do
  use Ecspanse.System,
    lock_components: [Demo.Components.Energy],
    event_subscriptions: [Demo.Events.EnergyTimerFinished]

  @impl true
  def run(%Demo.Events.EnergyTimerFinished{entity_id: entity_id}, _frame) do
    with {:ok, entity} <- Ecspanse.Query.fetch_entity(entity_id),
         {:ok, energy} <- Ecspanse.Query.fetch_component(entity, Demo.Components.Energy) do
      Ecspanse.Command.update_component!(energy, current: energy.current + 1)
    end
  end
end
```

The system locks the `Energy` component to update its state. And subscribes to the `EnergyTimerFinished` event because it is interested only in that timer event.

The system adds 1 point to the current energy. You are right to wonder why don't we first check the max energy cap. We will clarify this in the next section.

This system also introduces new ways of querying entities and components: `Ecspanse.Query.fetch_entity/1` and `Ecspanse.Query.fetch_component/2`.

**TIP**
The following functions would produce the same results:

```elixir
Ecspanse.Query.fetch_component(entity, Demo.Components.Energy)
#and
Demo.Components.Energy.fetch(entity)
```

### Rescheduling the Systems Execution

It is time to re-write the Demo module:

```elixir
defmodule Demo do
  use Ecspanse

  alias Demo.Systems

  @impl Ecspanse
  def setup(data) do
    data
    |> Ecspanse.add_startup_system(Systems.SpawnHero)
    |> Ecspanse.add_system(Systems.RestoreEnergy, run_if: [{__MODULE__, :energy_not_max?}])
    |> Ecspanse.add_system(Systems.MoveHero, run_after: [Systems.RestoreEnergy])
    |> Ecspanse.add_frame_end_system(Ecspanse.System.Timer)
  end

  def energy_not_max? do
    Ecspanse.Query.select({Demo.Components.Energy}, with: [Demo.Components.Hero])
    |> Ecspanse.Query.one()
    |> case do
      {%Demo.Components.Energy{current: current, max: max}} ->
        current < max

      _ ->
        false
    end
  end
end

```

#### The Conditional System Execution

By using the `:run_if` option, the `RestoreEnergy` system will run only if the current energy is below the max energy. The `energy_not_max?/0` function must always return a boolean value. Please note, this is not an efficient implementation. The `energy_not_max?/0` function will be called every frame. If the check would happen in the `RestoreEnergy` system, it would run only once every 3 seconds. But we took the opportunity to exemplify conditionally running systems.

#### The System Execution Order

By using the `:run_after` option, the `MoveHero` system will run after the `RestoreEnergy` system. Both are async systems, but even the async systems run in batches, not all at once. The batches are scheduled depending on the locked components and the specified order of execution of the systems.

> #### Note {: .info}
>
> It does not matter if the `RestoreEnergy` system actually runs this turn.
> The `MoveHero` will still run if receiving the `MoveHero` event.
> The `:run_after` option just guarantees that if both systems are running,
> the `MoveHero` will run after the `RestoreEnergy`.

#### Scheduling the Built-in Timer System

Once we start using timer-based components, the built-in `Ecspanse.System.Timer` system must be scheduled to run synchronously at the beginning or at the end of every frame. It will update all the timer-based components and trigger the timer events.

---

## Finding Resources

The goal of this chapter is to implement the resource gathering. With each move, the hero has a chance to find gold or gems.

> ### Ecspanse Concepts 4 {: .info}
>
> - using tags to manage collections of components
> - using advanced component specs
> - using component templates
> - using the auto-emitted component updated events

### Creating the Resource Template Component

Template components are used to define the structure for related components. It is a guarantee that certain components will have certain fields in their state.

Together with tags, this is a powerful way to achieve polymorphism in components.

```elixir
defmodule Demo.Components.Resource do
  use Ecspanse.Template.Component, state: [:id, :name, amount: 0], tags: [:resource]

  @impl true
  def validate(state) do
    with :ok <- validate_integer_amount(state[:amount]),
         :ok <- validate_positive_amount(state[:amount]) do
      :ok
    end
  end

  defp validate_integer_amount(amount) do
    if is_integer(amount) do
      :ok
    else
      {:error, "#{inspect(amount)} must be an integer"}
    end
  end

  defp validate_positive_amount(amount) do
    if amount >= 0 do
      :ok
    else
      {:error, "#{inspect(amount)} must be positive"}
    end
  end
end
```

Please note that the template `c:Ecspanse.Template.Component.validate/1` callback is optional. It runs only at compile time and it takes the list of state fields as argument.

### Creating the Resource Components

```elixir
defmodule Demo.Components.Gems do
  use Demo.Components.Resource,
    state: [id: :gems, name: "Gems", amount: 0], tags: [:resource]
end

defmodule Demo.Components.Gold do
  use Demo.Components.Resource,
    state: [id: :gems, name: "Gold", amount: 0], tags: [:resource]
end
```

As you can observe, the two components are invoking the newly defined template with `use Demo.Components.Resource` instead of `use Ecspanse.Component`.

Another new concept introduced both here and in the template definition is the `:tags` option. It is a list of atoms that can be used to group and query components. The resource components can now be used as a resource store for the user, but they can also be used to represent the cost of various items. We will handle the second use case in the next chapters.

For such cases, it is important to use a standardized approach, a perfect use-case for templates. E.g., all the resource components should have the same state fields.

### Adding the Resources Components to the Hero Entity

```elixir
defmodule Demo.Entities.Hero do
  #...

  def new do
    {Ecspanse.Entity,
     components: [
        #...
       {Components.Gold, [], [:available]},
       {Components.Gems, [], [:available]}
     ]}
  end
  #...
end
```

We use the `t:Ecspanse.Component.component_spec/0` type to specify the component spec. The first element of the tuple is the component module, the second element is the initial state of the component, and the third element is a list of tags.

The initial state of the component can be changed at runtime like `{Components.Gold, [amount: 5], [:available]}`. Also, new tags can be added at the time of the component creation. They will be appended to the list defined in the component module.

Runtime tag setting enables the reusability of components in various scenarios. It's important to note that changing a component's tags after it has been created is not supported.

### Storing Found Resources

Our new `MaybeFindResources` system subscribes to `Demo.Events.HeroMoved` emitted by the `MoveHero` system. Then it randomly decides if the current position contains resources, and the type of resource.

```elixir
defmodule Demo.Systems.MaybeFindResources do
  use Ecspanse.System,
    lock_components: [Demo.Components.Gems, Demo.Components.Gold],
    event_subscriptions: [Demo.Events.HeroMoved]

  alias Demo.Components

  @impl true
  def run(%Demo.Events.HeroMoved{}, _frame) do
    with true <- found_resource?(),
         resource_module <- pick_resource(),
         {:ok, hero_entity} <- Demo.Entities.Hero.fetch(),
         {:ok, resource} <- Ecspanse.Query.fetch_component(hero_entity, resource_module) do
      Ecspanse.Command.update_component!(resource, amount: resource.amount + 1)
    end
  end

  def run(_event, _frame), do: :ok

  defp found_resource?, do: Enum.random([true, false])
  defp pick_resource, do: Enum.random([Components.Gems, Components.Gold])
end
```

Here we take advantage of the standardized resource approach, so the system would update the resource amount without caring about the actual resource type.

Then we add the new system to the `setup`:

```elixir
defmodule Demo do
  use Ecspanse
  # ...
  def setup(data) do
    data
    # ...
    |> Ecspanse.add_system(Systems.MoveHero, run_after: [Systems.RestoreEnergy])
    |> Ecspanse.add_system(Systems.MaybeFindResources)
    |> Ecspanse.add_frame_end_system(Ecspanse.System.Timer)
  end
end
```

The last step of the current section is to expose the resources in the `fetch_hero_details/0` function in the `Demo.API` module.

```elixir
  defp list_hero_resources(hero_entity) do
    hero_entity
    |> Ecspanse.Query.list_tagged_components_for_entity([:resource, :available])
    |> Enum.map(&%{name: &1.name, amount: &1.amount})
  end
```

Here we use the `Ecspanse.Query.list_tagged_components_for_entity/2` function to get all the components tagged with `:resource` and `:available` for the hero entity.

The map returned by `fetch_hero_details/0` function should be updated with the new resources field:

```elixir
  %{
    # ...
    pos_y: position.y,
    resources: list_hero_resources(hero_entity),
  }
```

Starting the application and moving the hero around will now start to accumulate resources:

```iex
iex(14)> Demo.API.fetch_hero_details
%{
  name: "Hero",
  resources: [%{name: "Gems", amount: 2}, %{name: "Gold", amount: 5}],
  energy: 56,
  max_energy: 100,
  pos_x: -3,
  pos_y: -5
}
```

--

## Market and Inventory Items

The goal of this chapter is to implement inventory items and a market. The hero can buy items from the market with resources and store them in the inventory.

> ### Ecspanse Concepts 5 {: .info}
>
> - using relationships to manage collections of entities
> - querying components within entities relationships

### Inventory Items Components and Entities Specs

We start by defining the inventory items and the market components:

```elixir
defmodule Demo.Components.Market do
  use Ecspanse.Component
end

defmodule Demo.Components.Boots do
  use Ecspanse.Component, state: [name: "Boots"], tags: [:inventory]
end

defmodule Demo.Components.Compass do
  use Ecspanse.Component, state: [name: "Compass"], tags: [:inventory]
end

defmodule Demo.Components.Map do
  use Ecspanse.Component, state: [name: "Map"], tags: [:inventory]
end

defmodule Demo.Components.Potion do
  use Ecspanse.Component, state: [name: "Potion"], tags: [:inventory]
end
```

The inventory items, however are more complex than this. They cost resources, and in the future they may have various attributes impacting the hero's abilities. So the items will be entities of their own. We will create a new `Entities.Inventory` module to manage the inventory items specs.

```elixir
defmodule Demo.Entities.Inventory do
  alias Demo.Components

  @spec new_boots() :: Ecspanse.Entity.entity_spec()
  def new_boots do
    {Ecspanse.Entity, components: [Components.Boots, {Components.Gold, [amount: 3], [:cost]}]}
  end

  @spec new_compass() :: Ecspanse.Entity.entity_spec()
  def new_compass do
    {Ecspanse.Entity,
     components: [
       Components.Compass,
       {Components.Gold, [amount: 3], [:cost]},
       {Components.Gems, [amount: 2], [:cost]}
     ]}
  end

  @spec new_map() :: Ecspanse.Entity.entity_spec()
  def new_map do
    {Ecspanse.Entity, components: [Components.Map, {Components.Gold, [amount: 2], [:cost]}]}
  end

  @spec new_potion() :: Ecspanse.Entity.entity_spec()
  def new_potion do
    {Ecspanse.Entity, components: [Components.Potion, {Components.Gold, [amount: 1], [:cost]}]}
  end

  @spec list_inventory_components(Ecspanse.Entity.t()) :: [component :: struct()]
  def list_inventory_components(parent) do
    Ecspanse.Query.list_tagged_components_for_children(parent, [:inventory])
  end
end
```

Each item is defined together with their cost in resources. Please note that now we are using the `:cost` tag to mark the cost resource components.

The `list_inventory_components/1` function is used to list all the inventory items for a given parent entity. We will see what this means in the next section.

### Inventory Items as Children Entities

Let's start by updating the existing `SpawnHero` system.

```elixir
defmodule Demo.Systems.SpawnHero do
  use Ecspanse.System

  @impl true
  def run(_frame) do
    hero_entity = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Hero.new())
    potion_entity_1 = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Inventory.new_potion())
    potion_entity_2 = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Inventory.new_potion())
    boots_entity = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Inventory.new_boots())

    Ecspanse.Command.add_children!([ {hero_entity, [potion_entity_1, potion_entity_2, boots_entity]} ])
  end
end
```

The hero starts the journey with two potions and a pair of boots. We use the `Ecspanse.Command.add_children!/1` function to add the inventory items as children of the hero entity. This way we can build complex entities by composing smaller entities.

The Ecspanse library provides many helper functions to query and change entities relations.

The next step is to create a new system that spawns a market entity that holds more items.

```elixir
defmodule Demo.Systems.SpawnMarket do
  use Ecspanse.System

  @impl true
  def run(_frame) do
    compass_entity = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Inventory.new_compass())
    map_entity = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Inventory.new_map())

    Ecspanse.Command.spawn_entity!({ Ecspanse.Entity,
      components: [Demo.Components.Market], children: [compass_entity, map_entity]
    })
  end
end
```

This shows another way to spawn an entity with children already attached. The new system needs to be added to the `setup/1` as startup system:

```elixir
#...
|> Ecspanse.add_startup_system(Systems.SpawnMarket)
#...
```

One last thing we can do in this chapter is to add new functions to our API:

```elixir
defmodule Demo.API do
  #...
  defp list_hero_inventory(hero_entity) do
    hero_entity
    |> Demo.Entities.Inventory.list_inventory_components()
    |> Enum.map(&%{name: &1.name})
  end

  @spec fetch_market_items() :: {:ok, list(map())} | {:error, :not_found}
  def fetch_market_items do
    Ecspanse.Query.select({Ecspanse.Entity}, with: [Demo.Components.Market])
    |> Ecspanse.Query.one()
    |> case do
      {market_entity} -> {:ok, list_market_items(market_entity)}
      _ -> {:error, :not_found}
    end
  end

  defp list_market_items(market_entity) do
    market_entity
    |> Demo.Entities.Inventory.list_inventory_components()
    |> Enum.map(fn item_component ->
      item_entity = Ecspanse.Query.get_component_entity(item_component)

      %{entity_id: item_entity.id, name: item_component.name, cost: item_cost(item_entity)}
    end)
  end

  defp item_cost(item_entity) do
    item_entity
    |> Ecspanse.Query.list_tagged_components_for_entity([:resource, :cost])
    |> Enum.map(&%{name: &1.name, amount: &1.amount})
  end
end
```

The map returned by `fetch_hero_details/0` function should be updated with the new inventory field:

```elixir
  %{
    # ...
    pos_y: position.y,
    resources: list_hero_resources(hero_entity),
    inventory: list_hero_inventory(hero_entity)
  }
```

We will now display the hero's inventory and the market items with their respective prices.

We can test the new functions in the `iex` console:

```iex
iex(1)> Demo.API.fetch_hero_details()
%{
  name: "Hero",
  resources: [%{name: "Gems", amount: 0}, %{name: "Gold", amount: 0}],
  inventory: [%{name: "Boots"}, %{name: "Potion"}, %{name: "Potion"}],
  energy: 60,
  max_energy: 100,
  pos_x: 0,
  pos_y: 0
}

iex(1)> Demo.API.fetch_market_items()
[
  %{
    name: "Map",
    entity_id: "361c00ba-4dd3-4be8-b171-00e99c0b8ef7",
    cost: [%{name: "Gold", amount: 2}]
  },
  %{
    name: "Compass",
    entity_id: "b027fd01-d4fe-4ac1-9736-6b6f8c58fbd1",
    cost: [%{name: "Gold", amount: 3}, %{name: "Gems", amount: 2}]
  }
]
```

---

## Purchasing Items from the Market

The goal of this chapter is to allow the hero to purchase items from the market using resources.

> ### Ecspanse Concepts 6 {: .info}
>
> - in-depth entity relationships

### Purchasing Items Event

The event that triggers an item purchase is very simple:

```elixir
defmodule Demo.Events.PurchaseMarketItem do
  use Ecspanse.Event, fields: [:item_entity_id]
end
```

It stores only the ID of the entity of the item being purchased.
On the other hand, the system is a bit more complex.

### Purchasing Items System

Let's start with the code:

```elixir
defmodule Demo.Systems.PurchaseMarketItem do
  use Ecspanse.System, event_subscriptions: [Demo.Events.PurchaseMarketItem]

  @impl true
  def run(%Demo.Events.PurchaseMarketItem{item_entity_id: item_entity_id}, _frame) do
    with {:ok, item_entity} <- Ecspanse.Query.fetch_entity(item_entity_id),
         {:ok, market_entity} <- fetch_market_entity(),
         {:ok, hero_entity} <- Demo.Entities.Hero.fetch(),
         true <- Ecspanse.Query.is_child_of?(parent: market_entity, child: item_entity),
         hero_available_resources_components =
           Ecspanse.Query.list_tagged_components_for_entity(hero_entity, [:resource, :available]),
         item_cost_components =
           Ecspanse.Query.list_tagged_components_for_entity(item_entity, [:resource, :cost]),
         true <- has_enough_resources?(hero_available_resources_components, item_cost_components) do
      spend_resources(hero_available_resources_components, item_cost_components)
      Ecspanse.Command.remove_child!(market_entity, item_entity)
      Ecspanse.Command.add_child!(hero_entity, item_entity)
    end
  end

  defp fetch_market_entity do
    Ecspanse.Query.select({Ecspanse.Entity}, with: [Demo.Components.Market])
    |> Ecspanse.Query.one()
    |> case do
      {market_entity} -> {:ok, market_entity}
      _ -> {:error, :not_found}
    end
  end

  defp has_enough_resources?(available_resources, cost_resources) do
    Enum.all?(cost_resources, fn cost_resource ->
      Enum.any?(available_resources, fn available_resource ->
        available_resource.id == cost_resource.id &&
          available_resource.amount >= cost_resource.amount
      end)
    end)
  end

  defp spend_resources(available_resources, cost_resources) do
    Enum.each(cost_resources, fn cost_resource ->
      available_resource =
        Enum.find(available_resources, fn available_resource ->
          available_resource.id == cost_resource.id
        end)

      Ecspanse.Command.update_component!(available_resource,
        amount: available_resource.amount - cost_resource.amount
      )
    end)
  end
end
```

This system modifies many components, so one option is to make it synchronous. This way we don't have to individually lock each modified component. Later on it can be refactored into async if needed.

Before committing any component state changes it is important to perform all the required validations.

#### Validate Entities Exist

First of all, we want to make sure that the affected entities still exist. We use the `Ecspanse.Query.fetch_entity/1` function to validate that the item entity exists. For the market entity we implement a custom query, while for the hero, we use the helper function we created earlier.

#### Validate Relationships

We need to make sure that the item we want to purchase is still available in the market. In a multiplayer game scenario this would avoid race conditions where two players purchase the same item in the same time. We use the `Ecspanse.Query.is_child_of?/1` function to validate that the item is still a child of the market.

#### Validate Resources

Before the purchase is made, we need to make sure that the hero has enough resources to buy the item. Again, the tags prove useful. They allow us to query the same components from different entities and compare them.

#### Spending the Resources

Once all the validations are done, the resources can be spent. We iterate through the costs, then reduce the amount of the corresponding available resource.

#### Changing the Item Entity Parent

Finally, we remove the item from the market and add it to the hero's inventory. For this, we use the `Ecspanse.Command.remove_child!/2` and `Ecspanse.Command.add_child!/2` functions.

### The Purchase API

We first need to add the `PurchaseMarketItem` event to setup as sync system:

```elixir
#...
|> Ecspanse.add_frame_end_system(Systems.PurchaseMarketItem)
#...
```

Then expose the event in the API:

```elixir
@spec purchase_market_item(item_entity_id :: Ecspanse.Entity.id()) :: :ok
def purchase_market_item(item_entity_id) do
  Ecspanse.event({Demo.Events.PurchaseMarketItem, item_entity_id: item_entity_id})
end
```

Now we can test it in the console. First make sure that the hero has enough resources by walking around and using the exposed `fetch_hero_details/0` function. Then check the market items with `fetch_market_items/0` and note down the desired item entity ID. Purchase the item with `purchase_market_item/1`. Finally, check the hero details again to see the item in the inventory.

---

## Testing the Systems

The goal of this chapter is to learn how to test the systems. We will use the `MoveHero` system as an example.

> ### Ecspanse Concepts 7 {: .info}
>
> - testing systems in isolation
> - using a custom Ecspanse setup
> - using the system debugger to run systems manually

The game story is now ready. Time to see how we can test it.

Before we start, it is important to note that in test mode, the `Ecspanse.Server` is not automatically started. This allows us to decide the moment when the server should start, and what systems to run.

There are many ways to test systems. We will choose the most straightforward for this tutorial: testing the systems in isolation. That means that the systems scheduled under `Demo.setup/1` are not running. We will create a new setup function for testing, and call the systems manually.

```elixir
defmodule Demo.Systems.MoveHeroTest do
  use ExUnit.Case, async: false

  defmodule DemoTest do
    use Ecspanse
    @impl true
    def setup(data) do
      data
    end
  end

  setup do
    {:ok, _pid} = start_supervised({DemoTest, :test})
    Ecspanse.System.debug()

    hero_entity = %Ecspanse.Entity{} = Ecspanse.Command.spawn_entity!(Demo.Entities.Hero.new())
    {:ok, position_component} = Demo.Components.Position.fetch(hero_entity)

    assert position_component.x == 0
    assert position_component.y == 0

    {:ok, energy_component} = Demo.Components.Energy.fetch(hero_entity)
    assert energy_component.current == 50

    {:ok, hero_entity: hero_entity, energy_component: energy_component}
  end

  test "hero moves if enough energy", %{hero_entity: hero_entity} do
    event = move(:up)
    frame = frame(event)
    Demo.Systems.MoveHero.run(event, frame)

    {:ok, position_component} = Demo.Components.Position.fetch(hero_entity)
    assert position_component.x == 0
    assert position_component.y == 1

    {:ok, energy_component} = Demo.Components.Energy.fetch(hero_entity)
    assert energy_component.current == 49

    #...
  end

  test "hero doesn not move if not enough energy", %{
    hero_entity: hero_entity,
    energy_component: energy_component
  } do
    Ecspanse.Command.update_component!(energy_component, current: 0)

    event = move(:up)
    frame = frame(event)
    Demo.Systems.MoveHero.run(event, frame)

    {:ok, position_component} = Demo.Components.Position.fetch(hero_entity)
    assert position_component.x == 0
    assert position_component.y == 0

    {:ok, energy_component} = Demo.Components.Energy.fetch(hero_entity)
    assert energy_component.current == 0
  end

  defp move(direction) do
    %Demo.Events.MoveHero{direction: direction, inserted_at: System.os_time()}
  end

  defp frame(event) do
    %Ecspanse.Frame{event_batches: [[event]], delta: 1}
  end
end
```

### Test Dependencies

We start by creating a `DemoTest` module and implement a `setup/1` function that does not schedule any systems.

### Test Setup

There are 2 things happening at the top of the `setup` block:

- we manually start the server by passing the `{DemoTest, :test}` tuple to the `start_supervised/1` function. Compared to the normal setup where we add `Demo` to the supervision tree, the `{MODULE, :test}` tuple allows us to start the server in test mode.
- we run the `Ecspanse.System.debug/0` function. This function "upgrades" the current test PID to a system, which allows us to run systems manually. As mentioned previously, commands can be run only from inside a system. Making the test PID a system allows us to run commands directly in our tests.

For the rest of the setup block we setup the test data. We spawn a hero entity and fetch its position and energy components. We assert that the hero is at the starting position and has the starting energy.

### Test the Hero Can Move

We create two helper functions that would create a `MoveHero` event and a `t:Ecspanse.Frame.t/0` with the event in it.

Then we can run the `MoveHero` system manually by simply calling `Demo.Systems.MoveHero.run(event, frame)`.

From there on, we can query any component and do any relevant assertion. In this case, we assert that the hero has moved and that the energy has been reduced.

---

## Running the Demo

The code for this tutorial, together with instructions on how to run it in Livebook is available on [GitHub](https://github.com/iacobson/ecspanse_demo).

Also, you can find a more complex example of a multiplayer game built with Ecspanse on [GitHub](https://github.com/iacobson/iveseenthings).
