//! Line pipeline: constellation stick-figure GPU vertex count vs catalog.

use nightshade_planetarium::catalog::LINE_VERTEX_COUNT;
use nightshade_planetarium::renderer::{
    build_constellation_line_vertices, constellation_line_vertex_count,
};

#[test]
fn constellation_line_vertex_count_matches_catalog() {
    assert_eq!(LINE_VERTEX_COUNT, 728);
    assert_eq!(constellation_line_vertex_count(), LINE_VERTEX_COUNT);
    assert_eq!(build_constellation_line_vertices().len(), LINE_VERTEX_COUNT);
}
