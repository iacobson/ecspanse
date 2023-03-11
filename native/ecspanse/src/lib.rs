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

rustler::init!(
    "Elixir.Ecspanse.Native",
    [
        list_entities_components,
        query_filter_for_entities,
        query_filter_not_for_entities,
        query_filter_by_components
    ]
);
