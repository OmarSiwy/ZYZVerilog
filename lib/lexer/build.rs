use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    
    let dest_path = Path::new(&out_dir).join("lexer_info.rs");
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
    
    // Build C project using CMake + Ninja
    let project_root = Path::new(&manifest_dir);
    let c_build_dir = project_root.join("build");
    
    // Add rerun triggers for C project files
    println!("cargo:rerun-if-changed=CMakeLists.txt");
    println!("cargo:rerun-if-changed=src/*.c");
    println!("cargo:rerun-if-changed=inc/*.h");
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-changed=src/");
    println!("cargo:rustc-cfg=lexer_crate");
    
    // Check if CMakeLists.txt exists
    let cmake_file = project_root.join("CMakeLists.txt");
    if cmake_file.exists() {
        // Create build directory if it doesn't exist
        std::fs::create_dir_all(&c_build_dir).expect("Failed to create build directory");
        
        // Run CMake to generate Ninja build files
        let cmake_status = Command::new("cmake")
            .current_dir(&c_build_dir)
            .arg("-G")
            .arg("Ninja")
            .arg("-DCMAKE_BUILD_TYPE=Release")
            .arg("..")
            .status()
            .expect("Failed to execute cmake. Make sure CMake is installed.");
        
        if !cmake_status.success() {
            panic!("CMake configuration failed");
        }
        
        // Build with Ninja
        let ninja_status = Command::new("ninja")
            .current_dir(&c_build_dir)
            .status()
            .expect("Failed to execute ninja. Make sure Ninja is installed.");
        
        if !ninja_status.success() {
            panic!("Ninja build failed");
        }
        
        // Tell Cargo where to find the library and link against c library
        println!("cargo:rustc-link-search=native={}", c_build_dir.display());
        println!("cargo:rustc-link-lib=static=native");
    }
}
