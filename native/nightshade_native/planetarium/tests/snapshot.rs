//! Verifies the ArcSwap snapshot slot publishes the latest frame to readers.

use std::sync::Arc;
use std::thread;
use std::time::Duration;

use nightshade_planetarium::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC;
use nightshade_planetarium::scene::{
    load, new_snapshot_slot, publish, LabelCategory, LabelHint, SceneSnapshot, SelectedObject,
    SmallString,
};
use nightshade_planetarium::types::{AstroTime, Observer, ViewPose};

const FINAL_FRAME: u64 = 32;

fn snapshot_for_frame(frame_id: u64) -> SceneSnapshot {
    SceneSnapshot {
        frame_id,
        view_pose: ViewPose {
            ra_rad: frame_id as f64 * 0.01,
            ..ViewPose::default()
        },
        astro_time: AstroTime::from_jd_utc(DEFAULT_ASTRO_TIME_JD_UTC),
        observer: Observer::default(),
        labels: vec![LabelHint {
            object_id: frame_id,
            screen_x: 10.0,
            screen_y: 20.0,
            apparent_mag: 1.5,
            priority: 1,
            text: SmallString::from(format!("star-{frame_id}")),
            category: LabelCategory::Star,
        }],
        selected: Some(SelectedObject {
            object_id: frame_id,
            screen_x: 64.0,
            screen_y: 48.0,
            ra_rad: 1.0,
            dec_rad: 0.5,
            category: LabelCategory::Star,
            display_name: SmallString::from("Vega"),
        }),
        constellation_art: Vec::new(),
    }
}

#[test]
fn reader_sees_latest_published_snapshot() {
    let slot = new_snapshot_slot();
    let reader_slot = Arc::clone(&slot);
    let publisher_slot = Arc::clone(&slot);

    let publisher = thread::spawn(move || {
        for frame_id in 1..=FINAL_FRAME {
            publish(&publisher_slot, snapshot_for_frame(frame_id));
            thread::sleep(Duration::from_millis(1));
        }
    });

    let reader = thread::spawn(move || {
        let mut last_seen = 0u64;
        loop {
            let snap = load(&reader_slot);
            if snap.frame_id > last_seen {
                last_seen = snap.frame_id;
            }
            if last_seen >= FINAL_FRAME {
                return last_seen;
            }
            thread::sleep(Duration::from_millis(1));
        }
    });

    publisher.join().expect("publisher thread panicked");
    let seen = reader.join().expect("reader thread panicked");
    assert_eq!(seen, FINAL_FRAME);

    let latest = load(&slot);
    assert_eq!(latest.frame_id, FINAL_FRAME);
    assert!((latest.view_pose.ra_rad - (FINAL_FRAME as f64 * 0.01)).abs() < 1e-9);
    assert_eq!(latest.labels.len(), 1);
    assert_eq!(latest.labels[0].object_id, FINAL_FRAME);
    assert_eq!(
        latest.labels[0].text.as_str(),
        format!("star-{FINAL_FRAME}")
    );
    let selected = latest.selected.as_ref().expect("expected selection");
    assert_eq!(selected.object_id, FINAL_FRAME);
    assert_eq!(selected.display_name.as_str(), "Vega");
}
