//! Cache keying and eviction.

use std::sync::Arc;

use serde_json::json;

use super::*;
use crate::recipe::model::{OpContext, RecipeAuthor, RecipeStep};
use crate::recipe::render::{StepOutcome, StepReport};
use crate::recipe::testkit::{fixed_catalog, synthetic_star_field};

fn recipe_of(steps: Vec<RecipeStep>) -> Recipe {
    let mut recipe = Recipe::new("rec", "master-1", RecipeAuthor::User);
    recipe.steps = steps;
    recipe
}

fn three_step_recipe() -> Recipe {
    recipe_of(vec![
        RecipeStep::new("test_scale", 1).with_params(json!({"factor": 2.0})),
        RecipeStep::new("test_scale", 1).with_params(json!({"factor": 3.0})),
        RecipeStep::new("test_scale", 1).with_params(json!({"factor": 5.0})),
    ])
}

fn report(index: usize) -> Arc<Vec<StepReport>> {
    Arc::new(
        (0..=index)
            .map(|i| StepReport {
                index: i,
                op_id: "test_scale".to_string(),
                op_version: 1,
                outcome: StepOutcome::Applied,
            })
            .collect(),
    )
}

#[test]
fn a_key_is_stable_for_the_same_prefix() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let ctx = OpContext::new();
    let recipe = three_step_recipe();
    assert_eq!(
        CacheKey::for_prefix(&recipe, &base, &ctx, 1),
        CacheKey::for_prefix(&recipe, &base, &ctx, 1)
    );
}

#[test]
fn editing_a_step_changes_that_boundary_and_the_ones_above_it() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let ctx = OpContext::new();
    let before = three_step_recipe();
    let mut after = three_step_recipe();
    after.steps[1].params = json!({"factor": 4.0});

    assert_eq!(
        CacheKey::for_prefix(&before, &base, &ctx, 0),
        CacheKey::for_prefix(&after, &base, &ctx, 0),
        "the boundary below the edit is untouched"
    );
    assert_ne!(
        CacheKey::for_prefix(&before, &base, &ctx, 1),
        CacheKey::for_prefix(&after, &base, &ctx, 1)
    );
    assert_ne!(
        CacheKey::for_prefix(&before, &base, &ctx, 2),
        CacheKey::for_prefix(&after, &base, &ctx, 2)
    );
}

#[test]
fn disabling_a_step_returns_to_the_key_below_it() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let ctx = OpContext::new();
    let mut recipe = three_step_recipe();
    recipe.steps[2].enabled = false;
    assert_eq!(
        CacheKey::for_prefix(&recipe, &base, &ctx, 2),
        CacheKey::for_prefix(&recipe, &base, &ctx, 1)
    );
}

#[test]
fn a_different_pyramid_level_is_a_different_key() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let recipe = three_step_recipe();
    assert_ne!(
        CacheKey::for_prefix(&recipe, &base, &OpContext::new(), 0),
        CacheKey::for_prefix(&recipe, &base, &OpContext::new().at_level(1), 0)
    );
}

#[test]
fn attaching_a_catalog_is_a_different_key() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let recipe = three_step_recipe();
    assert_ne!(
        CacheKey::for_prefix(&recipe, &base, &OpContext::new(), 0),
        CacheKey::for_prefix(
            &recipe,
            &base,
            &OpContext::new().with_catalog(fixed_catalog()),
            0
        )
    );
}

#[test]
fn a_different_base_geometry_is_a_different_key() {
    let recipe = three_step_recipe();
    let ctx = OpContext::new();
    assert_ne!(
        CacheKey::for_prefix(&recipe, &synthetic_star_field(8, 8, 1, 1), &ctx, 0),
        CacheKey::for_prefix(&recipe, &synthetic_star_field(16, 8, 1, 1), &ctx, 0)
    );
}

#[test]
fn a_different_base_master_ref_is_a_different_key() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let ctx = OpContext::new();
    let mut other = three_step_recipe();
    other.base_master_ref = "master-2".to_string();
    assert_ne!(
        CacheKey::for_prefix(&three_step_recipe(), &base, &ctx, 0),
        CacheKey::for_prefix(&other, &base, &ctx, 0)
    );
}

#[test]
fn a_key_fingerprint_is_thirty_two_hex_digits() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let fingerprint = key.fingerprint();
    assert_eq!(fingerprint.len(), 32);
    assert!(fingerprint.chars().all(|c| c.is_ascii_hexdigit()));
    assert!(key.as_str().contains("master-1"));
}

#[test]
fn a_stored_boundary_comes_back_with_its_reports() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let mut cache = RenderCache::unbounded();
    cache.insert(key.clone(), Arc::new(base.clone()), report(0));
    assert!(cache.contains(&key));
    let (image, reports) = cache.get(&key).expect("the boundary is stored");
    assert_eq!(image.len(), base.len());
    assert_eq!(reports.len(), 1);
    assert_eq!(cache.hits(), 1);
    assert_eq!(cache.misses(), 0);
}

#[test]
fn a_missing_boundary_counts_a_miss() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let mut cache = RenderCache::unbounded();
    assert!(cache.get(&key).is_none());
    assert_eq!(cache.misses(), 1);
    cache.reset_stats();
    assert_eq!(cache.misses(), 0);
}

#[test]
fn a_disabled_cache_stores_nothing() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let mut cache = RenderCache::disabled();
    cache.insert(key.clone(), Arc::new(base), report(0));
    assert!(cache.is_empty());
    assert!(cache.get(&key).is_none());
}

#[test]
fn the_least_recently_used_boundary_is_evicted_first() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let bytes = base.byte_size();
    let recipe = three_step_recipe();
    let ctx = OpContext::new();
    let keys: Vec<CacheKey> = (0..3)
        .map(|i| CacheKey::for_prefix(&recipe, &base, &ctx, i))
        .collect();

    let mut cache = RenderCache::new(bytes * 2);
    let image = Arc::new(base);
    cache.insert(keys[0].clone(), Arc::clone(&image), report(0));
    cache.insert(keys[1].clone(), Arc::clone(&image), report(1));
    // Touch the oldest so the middle one becomes least recently used.
    assert!(cache.get(&keys[0]).is_some());
    cache.insert(keys[2].clone(), Arc::clone(&image), report(2));

    assert_eq!(cache.len(), 2);
    assert!(cache.contains(&keys[0]));
    assert!(!cache.contains(&keys[1]));
    assert!(cache.contains(&keys[2]));
    assert_eq!(cache.used_bytes(), bytes * 2);
}

#[test]
fn a_boundary_larger_than_the_whole_budget_is_not_stored() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let mut cache = RenderCache::new(base.byte_size() - 1);
    cache.insert(key.clone(), Arc::new(base), report(0));
    assert!(cache.is_empty());
    assert_eq!(cache.used_bytes(), 0);
}

#[test]
fn re_inserting_a_key_does_not_double_count_its_bytes() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let bytes = base.byte_size();
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let mut cache = RenderCache::unbounded();
    let image = Arc::new(base);
    cache.insert(key.clone(), Arc::clone(&image), report(0));
    cache.insert(key, Arc::clone(&image), report(0));
    assert_eq!(cache.len(), 1);
    assert_eq!(cache.used_bytes(), bytes);
}

#[test]
fn clearing_drops_every_boundary_and_keeps_the_counters() {
    let base = synthetic_star_field(8, 8, 1, 1);
    let key = CacheKey::for_prefix(&three_step_recipe(), &base, &OpContext::new(), 0);
    let mut cache = RenderCache::unbounded();
    cache.insert(key.clone(), Arc::new(base), report(0));
    assert!(cache.get(&key).is_some());
    cache.clear();
    assert!(cache.is_empty());
    assert_eq!(cache.used_bytes(), 0);
    assert_eq!(cache.hits(), 1);
}

#[test]
fn the_default_cache_carries_the_documented_budget() {
    assert_eq!(
        RenderCache::default().capacity_bytes(),
        DEFAULT_CACHE_CAPACITY_BYTES
    );
}
