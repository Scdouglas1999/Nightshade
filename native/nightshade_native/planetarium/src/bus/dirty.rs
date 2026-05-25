bitflags::bitflags! {
    /// Bitset of renderer subsystems that need refresh after a command.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
    pub struct DirtyFlags: u32 {
        const POSE      = 1 << 0;
        const TIME      = 1 << 1;
        const OBSERVER  = 1 << 2;
        const CONFIG    = 1 << 3;
        const MOUNT     = 1 << 4;
        const FOV       = 1 << 5;
        const MOSAIC    = 1 << 6;
        const HORIZON   = 1 << 7;
        const CATALOG   = 1 << 8;
        const SELECTION = 1 << 9;
        const RESIZE    = 1 << 10;
    }
}
