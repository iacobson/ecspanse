# Ecspanse

[![Ecspanse](./guides/images/logo_small.png)](https://github.com/iacobson/ecspanse_demo)
[![Hex Version](https://img.shields.io/hexpm/v/ecspanse.svg)](https://hex.pm/packages/ecspanse)
[![License](https://img.shields.io/hexpm/l/ecspanse.svg)](https://github.com/iacobson/ecspanse/blob/main/LICENSE)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/ecspanse)

Ecspanse is an Entity Component System (ECS) framework for Elixir.

Ecspanse is not a game engine, but a flexible foundation
for managing state and building logic offering features like:

- flexible queries with multiple filters
- dynamic bidirectional relationships
- versatile tagging capabilities
- system event subscriptions
- asynchronous system execution

The full documentation for the Ecspanse project is available on [HexDocs](https://hexdocs.pm/ecspanse).

Ecspanse draws inspiration from the API of [bevy_ecs](https://docs.rs/bevy_ecs/latest/bevy_ecs/). However, while [Bevy](https://bevyengine.org/learn/book/getting-started/ecs/) is a comprehensive game engine, Ecspanse focuses on providing an Entity Component System (ECS) library in Elixir. The concepts described in [the unofficial cheat book](https://bevy-cheatbook.github.io/programming/ecs-intro.html) also served as valuable references during development.

Please note that Ecspanse does not claim to be a Bevy equivalent in Elixir. If you're seeking a fully-featured ECS game library, please give [Bevy](https://bevyengine.org/) a try.

## Installation

Refer to the [Getting Started](https://hexdocs.pm/ecspanse/getting_started.html) guide for installation instructions.

## Getting Started

The step-by-step [Tutorial](https://hexdocs.pm/ecspanse/tutorial.html) guides you through building a simple game, introducing key features of the framework along the way.

## Demo Projects

### The Ecspanse Demo

This is the code used in the [Ecspanse Tutorial](https://hexdocs.pm/ecspanse/tutorial.html). You can find it on [GitHub](https://github.com/iacobson/ecspanse_demo).

### I've Seen Things

This multiplayer game was built with Ecspanse during the library's development. Check out its [GitHub repository](https://github.com/iacobson/iveseenthings). The game is currently hosted on [fly.io](https://fly.io/) and can be played [HERE](https://iveseenthings.fly.dev/).

## To Do

- [ ] Implement persistence: Develop a flexible and selective method for saving and loading components and resources.
- [ ] Expand testing beyond happy path scenarios.
- [ ] Improve documentation.

## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [https://www.apache.org/licenses/LICENSE-2.0](https://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
