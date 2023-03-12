#![warn(clippy::all, clippy::pedantic)] // use rustler::{Atom, Encoder, Env, Term};

use itertools::Itertools;
use rayon::prelude::*;
use rustler::{Atom, Encoder, Env, NifStruct, Term};
use std::collections::HashMap;

#[derive(NifStruct)]
#[module = "Ecspanse.Entity"]
pub struct Entity {
    id: String,
}

#[derive(NifStruct)]
#[module = "Ecspanse.Query.WithComponents"]
pub struct QueryWithComponents {
    with: Vec<Atom>,
    without: Vec<Atom>,
}

// Returns a map with entity IDs as keys and a list of components as values
// This function is reused in Queries and Commands to determine if certain Entities have certain Components
#[rustler::nif]
fn list_entities_components(env: Env, list: Vec<(String, Atom)>) -> Term {
    let result: HashMap<String, Vec<Atom>> = list.into_iter().into_group_map();

    result.encode(env)
}

// Checks for selected entities and filters the entities_components map
#[rustler::nif]
fn query_filter_for_entities(
    env: Env,
    entities_components: HashMap<String, Vec<Atom>>,
    filter_entities: Vec<Entity>,
) -> Term {
    if filter_entities.is_empty() {
        entities_components.encode(env)
    } else {
        let mut result = HashMap::new();

        for entity in filter_entities {
            if let Some(components) = entities_components.get(&entity.id) {
                result.insert(entity.id, components);
            }
        }

        result.encode(env)
    }
}

// Checks for rejected entities and filters the entities_components map
#[rustler::nif]
fn query_filter_not_for_entities(
    env: Env,
    entities_components: HashMap<String, Vec<Atom>>,
    reject_entities: Vec<Entity>,
) -> Term {
    let mut result = entities_components;

    for entity in reject_entities {
        result.remove(&entity.id);
    }

    result.encode(env)
}

// Check if the entities have selected and do not have rejected components
// Returns a list of unique entity IDs
#[rustler::nif]
fn query_filter_by_components(
    env: Env,
    entities_components: HashMap<String, Vec<Atom>>,
    components: Vec<QueryWithComponents>,
) -> Term {
    components
        .par_iter()
        .flat_map(|comp| {
            entities_components
                .par_iter()
                .filter(|(_, component_modules)| {
                    let has_with_components = comp
                        .with
                        .iter()
                        .all(|elem| component_modules.contains(elem));
                    let does_not_have_without_components = !comp
                        .without
                        .iter()
                        .any(|elem| component_modules.contains(elem));

                    has_with_components && does_not_have_without_components
                })
                .map(|(entity_id, _)| entity_id.clone())
                .collect::<Vec<String>>()
        })
        .collect::<Vec<String>>()
        .into_iter()
        .unique()
        .collect::<Vec<String>>()
        .encode(env)
}

// TODO: could not use parallel iteration because it's not safe to share env between threads
// Building query return vectors for mandatory and optional components.
// The vectors are converted to tuples on the Elixir side
#[rustler::nif]
fn build_return_vectors<'a>(
    env: Env<'a>,
    return_entity: bool,
    select_components: Vec<Atom>,
    select_optional_components: Vec<Atom>,
    entity_ids: Vec<String>,
    filtered_components_map: HashMap<Term<'a>, Term<'a>>,
) -> Term<'a> {
    let mut result = Vec::new();
    for entity_id in &entity_ids {
        let mut record = Vec::new();
        let mut clear = true;

        if return_entity {
            let entity = Entity {
                id: entity_id.clone(),
            };
            record.push(entity.encode(env));
        }

        for comp in &select_components {
            let key = (entity_id, comp).encode(env);
            if let Some(value) = filtered_components_map.get(&key) {
                record.push(*value);
            } else {
                clear = false;
                break;
            }
        }

        for comp in &select_optional_components {
            let key = (entity_id, comp).encode(env);
            if let Some(value) = filtered_components_map.get(&key) {
                record.push(*value);
            } else {
                record.push(rustler::types::atom::nil().encode(env));
            }
        }

        if clear {
            result.push(record);
        }
    }

    result.encode(env)
}

rustler::init!(
    "Elixir.Ecspanse.Native",
    [
        list_entities_components,
        query_filter_for_entities,
        query_filter_not_for_entities,
        query_filter_by_components,
        build_return_vectors
    ]
);
