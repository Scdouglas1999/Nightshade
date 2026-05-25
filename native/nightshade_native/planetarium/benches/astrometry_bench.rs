//! Hot-path astrometry benchmarks with per-plan latency budgets (Task 32).
//!
//! ```text
//! cargo bench -p nightshade_planetarium --bench astrometry_bench
//! ```
//!
//! Median sample time must stay under each budget (nanoseconds). Set
//! `ASTROMETRY_BENCH_NO_GATE=1` to print results without failing the process.

use std::hint::black_box;
use std::time::Instant;

use nightshade_planetarium::astrometry::frames::FrameChain;
use nightshade_planetarium::astrometry::kepler::solve_kepler;
use nightshade_planetarium::astrometry::moon::moon_equatorial_j2000_from_jd_tt;
use nightshade_planetarium::astrometry::vsop87::{
    julian_millennia_tt, planet_equatorial_rad, sun_geocentric_ecliptic, VsopBody,
};
use nightshade_planetarium::types::{AstroTime, Observer};

/// FrameChain::build — plan budget <5 µs.
const BUDGET_FRAME_CHAIN_BUILD_NS: u64 = 5_000;
/// VSOP87 Sun (geocentric ecliptic) — plan budget <2 µs.
const BUDGET_VSOP87_SUN_NS: u64 = 2_000;
/// VSOP87 planet (Jupiter equatorial) — plan budget <5 µs.
const BUDGET_VSOP87_PLANET_NS: u64 = 5_000;
/// ELP2000-82B truncated Moon equatorial — plan budget <10 µs.
const BUDGET_ELP_MOON_NS: u64 = 10_000;
/// Kepler equation solve (one iteration path) — plan budget <1 µs.
const BUDGET_KEPLER_ITER_NS: u64 = 1_000;

/// Representative epoch: 2024-06-15 00:00 UTC (typical night-sky session).
const JD_UTC_BENCH: f64 = 2_460_466.5;

struct BenchCase {
    name: &'static str,
    budget_ns: u64,
    measure_ns: fn() -> u64,
}

fn median_ns_per_op(mut samples: Vec<u64>) -> u64 {
    samples.sort_unstable();
    samples[samples.len() / 2]
}

/// Time one operation; returns nanoseconds per call (median of several runs).
fn bench_ns_per_op(warmup_iters: u32, measure: impl Fn()) -> u64 {
    for _ in 0..warmup_iters {
        measure();
    }

    let mut medians = Vec::with_capacity(7);
    for _ in 0..7 {
        let target_ns = 10_000_000u64; // ≥10 ms per sample window
        let start = Instant::now();
        let mut iters = 0u64;
        loop {
            measure();
            iters += 1;
            if start.elapsed().as_nanos() as u64 >= target_ns {
                break;
            }
        }
        let elapsed_ns = start.elapsed().as_nanos() as u64;
        medians.push(elapsed_ns / iters.max(1));
    }
    median_ns_per_op(medians)
}

fn bench_jd_tt() -> f64 {
    AstroTime::from_jd_utc(JD_UTC_BENCH).jd_tt
}

fn frame_chain_build_ns() -> u64 {
    let time = AstroTime::from_jd_utc(JD_UTC_BENCH);
    let observer = Observer {
        latitude_rad: 45.0_f64.to_radians(),
        longitude_rad: 6.0_f64.to_radians(),
        elevation_m: 800.0,
        pressure_hpa: 1010.0,
        temperature_c: 12.0,
    };
    bench_ns_per_op(200, || {
        black_box(FrameChain::build(black_box(time), black_box(observer)));
    })
}

fn vsop87_sun_ns() -> u64 {
    let t = julian_millennia_tt(bench_jd_tt());
    bench_ns_per_op(500, || {
        black_box(sun_geocentric_ecliptic(black_box(t)));
    })
}

fn vsop87_planet_ns() -> u64 {
    bench_ns_per_op(300, || {
        black_box(planet_equatorial_rad(
            black_box(VsopBody::Jupiter),
            black_box(bench_jd_tt()),
        ));
    })
}

fn elp_moon_ns() -> u64 {
    bench_ns_per_op(200, || {
        black_box(moon_equatorial_j2000_from_jd_tt(black_box(bench_jd_tt())));
    })
}

fn kepler_iter_ns() -> u64 {
    // Ceres-like moderate eccentricity (Newton path).
    let m = 1.048_f64;
    let e = 0.076_f64;
    bench_ns_per_op(1000, || {
        black_box(solve_kepler(black_box(m), black_box(e)));
    })
}

fn run_cases(cases: &[BenchCase], gate: bool) -> bool {
    let mut all_ok = true;
    println!(
        "astrometry benchmarks (median ns/op, budgets from planetarium-v2 plan Task 32)\n"
    );
    println!(
        "{:<28} {:>10} {:>10} {:>8}",
        "case", "median_ns", "budget_ns", "status"
    );
    println!("{}", "-".repeat(60));

    for case in cases {
        let median = (case.measure_ns)();
        let ok = median <= case.budget_ns;
        if !ok {
            all_ok = false;
        }
        let status = if ok { "OK" } else { "OVER" };
        println!(
            "{:<28} {:>10} {:>10} {:>8}",
            case.name, median, case.budget_ns, status
        );
    }

    let total_budget_ns: u64 = BUDGET_FRAME_CHAIN_BUILD_NS
        + BUDGET_VSOP87_SUN_NS
        + BUDGET_VSOP87_PLANET_NS
        + BUDGET_ELP_MOON_NS
        + BUDGET_KEPLER_ITER_NS;
    println!("{}", "-".repeat(60));
    println!(
        "per-frame astrometry budget (sum of above): ~{total_budget_ns} ns (~{} µs)",
        total_budget_ns / 1000
    );

    if gate && !all_ok {
        eprintln!("\nastrometry bench FAILED: one or more cases exceeded budget.");
        eprintln!("Set ASTROMETRY_BENCH_NO_GATE=1 to report without exiting non-zero.");
    } else if !all_ok {
        eprintln!("\nastrometry bench: over budget (gating disabled).");
    } else {
        println!("\nastrometry bench: all cases within budget.");
    }

    all_ok
}

fn main() {
    let gate = std::env::var("ASTROMETRY_BENCH_NO_GATE").is_err();

    let cases = [
        BenchCase {
            name: "frame_chain_build",
            budget_ns: BUDGET_FRAME_CHAIN_BUILD_NS,
            measure_ns: frame_chain_build_ns,
        },
        BenchCase {
            name: "vsop87_sun",
            budget_ns: BUDGET_VSOP87_SUN_NS,
            measure_ns: vsop87_sun_ns,
        },
        BenchCase {
            name: "vsop87_planet_jupiter",
            budget_ns: BUDGET_VSOP87_PLANET_NS,
            measure_ns: vsop87_planet_ns,
        },
        BenchCase {
            name: "elp_moon_equatorial",
            budget_ns: BUDGET_ELP_MOON_NS,
            measure_ns: elp_moon_ns,
        },
        BenchCase {
            name: "kepler_solve",
            budget_ns: BUDGET_KEPLER_ITER_NS,
            measure_ns: kepler_iter_ns,
        },
    ];

    let ok = run_cases(&cases, gate);
    if gate && !ok {
        std::process::exit(1);
    }
}
