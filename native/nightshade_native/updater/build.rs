//! Build script to embed Windows manifest for admin elevation

fn main() {
    #[cfg(windows)]
    {
        if std::env::var("PROFILE").as_deref() != Ok("release") {
            return;
        }

        let mut res = winres::WindowsResource::new();
        res.set_manifest_file("updater.manifest");
        if let Err(e) = res.compile() {
            eprintln!("Warning: Failed to embed manifest: {}", e);
        }
    }
}
