//! HEALPix tile format: zerocopy round-trip (memory + mmap).

use std::fs;
use std::io::Write;

use memmap2::Mmap;
use nightshade_planetarium::catalog::{
    LodEntry, StarRecord, TileHeader, encode_tile, parse_tile, tile_byte_len,
};

fn sample_tile() -> (TileHeader, Vec<LodEntry>, Vec<StarRecord>) {
    let stars = vec![
        StarRecord::from_radec(11767, 0.0, std::f32::consts::FRAC_PI_2, 2.02, 0.60, 0),
        StarRecord::from_radec(91262, 4.25, 0.11, 0.03, 0.00, 0),
        StarRecord::from_radec(32349, 1.76, -0.47, 1.46, 0.00, 1),
    ];
    let lods = vec![
        LodEntry {
            mag_threshold: 2.5,
            start_offset: 0,
            count: 1,
            reserved: 0,
        },
        LodEntry {
            mag_threshold: 6.0,
            start_offset: 1,
            count: 2,
            reserved: 0,
        },
    ];
    let header = TileHeader::new(1, 1, 8, 42, stars.len() as u32, lods.len() as u32);
    (header, lods, stars)
}

#[test]
fn round_trip_in_memory() {
    let (header, lods, stars) = sample_tile();
    let bytes = encode_tile(&header, &lods, &stars);
    assert_eq!(bytes.len(), tile_byte_len(lods.len(), stars.len()));

    let parsed = parse_tile(&bytes).expect("parse in-memory tile");
    assert_eq!(*parsed.header, header);
    assert_eq!(parsed.lod_entries, lods.as_slice());
    assert_eq!(parsed.stars, stars.as_slice());
}

#[test]
fn round_trip_mmap_tempfile() {
    let (header, lods, stars) = sample_tile();
    let bytes = encode_tile(&header, &lods, &stars);

    let dir = std::env::temp_dir().join("nightshade_planetarium_tile_test");
    fs::create_dir_all(&dir).expect("temp dir");
    let path = dir.join("tile_42.bin");
    let mut file = fs::File::create(&path).expect("create temp tile");
    file.write_all(&bytes).expect("write tile");
    drop(file);

    let file = fs::File::open(&path).expect("reopen tile");
    // SAFETY: test owns the file; no concurrent writers.
    let mmap = unsafe { Mmap::map(&file).expect("mmap tile") };
    let parsed = parse_tile(&mmap).expect("parse mmap tile");

    assert_eq!(*parsed.header, header);
    assert_eq!(parsed.lod_entries, lods.as_slice());
    assert_eq!(parsed.stars, stars.as_slice());

    let _ = fs::remove_file(path);
}

#[test]
fn rejects_bad_magic() {
    let (mut header, lods, stars) = sample_tile();
    header.magic = *b"BADMAGIC";
    let bytes = encode_tile(&header, &lods, &stars);
    let err = parse_tile(&bytes).expect_err("bad magic");
    assert!(matches!(err, nightshade_planetarium::catalog::TileParseError::BadMagic));
}
