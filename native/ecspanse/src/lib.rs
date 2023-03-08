#![warn(clippy::all, clippy::pedantic)] // use rustler::{Atom, Encoder, Env, Term};

use itertools::Itertools;
use rustler::{Atom, Encoder, Env, Term};
use std::collections::HashMap;

#[rustler::nif]
fn list_entities_components(env: Env, list: Vec<(String, Atom)>) -> Term {
    let result: HashMap<String, Vec<Atom>> = list.into_iter().into_group_map();

    result.encode(env)
}
rustler::init!("Elixir.Ecspanse.Native", [list_entities_components]);
