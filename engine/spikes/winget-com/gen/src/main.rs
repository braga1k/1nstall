fn main() {
    let args = ["--in", "Microsoft.Management.Deployment.winmd", "default", "--out", "spike/src/bindings.rs", "--filter", "Microsoft.Management.Deployment", "--reference", "windows,skip-root,Windows", "--no-comment"];
    let warnings = windows_bindgen::bindgen(args);
    println!("{warnings}");
}
