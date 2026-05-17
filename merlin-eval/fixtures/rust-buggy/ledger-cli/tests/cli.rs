use std::process::Command;

/// RL4 - `add` must reject a non-numeric amount, not silently accept it.
#[test]
fn add_rejects_non_numeric_amount() {
    let dir = std::env::temp_dir().join(format!("ledgercli-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let exe = env!("CARGO_BIN_EXE_ledger-cli");

    let out = Command::new(exe)
        .args(["add", "abc", "food"])
        .current_dir(&dir)
        .output()
        .unwrap();

    assert!(
        !out.status.success(),
        "`add abc food` must fail - a non-numeric amount is an error, not a 0 entry"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
