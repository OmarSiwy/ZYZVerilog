use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("analysis_info.rs");
    
    let build_info = format!(
        r#"pub const BUILD_TIME: &str = "{}";
pub const PKG_VERSION: &str = "{}";
pub const PKG_NAME: &str = "{}";
"#,
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        env::var("CARGO_PKG_VERSION").unwrap(),
        env::var("CARGO_PKG_NAME").unwrap()
    );
    
    fs::write(&dest_path, build_info).unwrap();
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-changed=src/");
    println!("cargo:rustc-cfg=analysis_crate");
}
