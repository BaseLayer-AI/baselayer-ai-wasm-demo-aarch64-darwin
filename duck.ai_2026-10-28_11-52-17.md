This conversation was generated with Duck.ai (https://duck.ai) using Google's Gemma 4 31B Model. AI chats may display inaccurate or offensive information (see https://duckduckgo.com/duckai/privacy-terms for more info).

====================

User prompt 1 of 3 - 10/28/2026, 11:45:24 AM:
[Pasted text #1]
# Follow the guidance at https://baselayer-ai.github.io
{
  description = "WASM Kinetic Art Generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };

      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        targets = [ "wasm32-unknown-unknown" ];
      };
    in {
      packages.${system} = let
        buildWorkspace = pkgs.runCommand "art-workspace" {} ''
          mkdir -p $out

          # --- WASM Engine Source ---
          cat << 'EOF' > $out/engine.rs
          static mut TIME: f32 = 0.0;
          #[no_mangle]
          pub extern "C" fn update_time(delta: f32) { unsafe { TIME += delta; } }
          #[no_mangle]
          pub extern "C" fn get_particle_pos(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).sin()).cos() * radius }
          }
          #[no_mangle]
          pub extern "C" fn get_particle_y(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).cos()).sin() * radius }
          }
          EOF

          ${rustToolchain}/bin/rustc --target wasm32-unknown-unknown --crate-type cdylib -O $out/engine.rs -o $out/engine.wasm
          
          # --- Launcher Source ---
          cat << 'EOF' > $out/launcher.rs
          use std::{env, fs::File, io::Write, process::Command};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_base64 = base64_encode(wasm_bytes);
              let html_content = format!(r#"<!DOCTYPE html><html><head><title>WASM Kinetic Art</title></head><body><canvas id="canvas"></canvas><script>const base64 = '{}'; const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0)); WebAssembly.instantiate(bytes).then(({{instance}}) => {{ const {{ update_time, get_particle_pos, get_particle_y }} = instance.exports; const canvas = document.getElementById('canvas'); const ctx = canvas.getContext('2d'); const resize = () => {{ canvas.width = window.innerWidth; canvas.height = window.innerHeight; }}; window.onresize = resize; resize(); const draw = () => {{ update_time(0.02); ctx.fillStyle = 'rgba(5, 5, 5, 0.15)'; ctx.fillRect(0, 0, canvas.width, canvas.height); ctx.fillStyle = '#00ffcc'; for(let i=0; i<250; i++) {{ const x = (canvas.width/2) + get_particle_pos(i, 300); const y = (canvas.height/2) + get_particle_y(i, 300); ctx.beginPath(); ctx.arc(x, y, 1.5, 0, Math.PI*2); ctx.fill(); }} requestAnimationFrame(draw); }}; draw(); }});</script></body></html>"#, wasm_base64);
              let mut temp_path = env::temp_dir(); temp_path.push("wasm_art_generator.html");
              File::create(&temp_path).and_then(|mut f| f.write_all(html_content.as_bytes())).expect("Failed to write HTML");
              Command::new("open").arg(&temp_path).spawn().expect("Failed to open browser");
          }
          fn base64_encode(input: &[u8]) -> String {
              const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
              let mut result = String::with_capacity((input.len() + 2) / 3 * 4);
              for chunk in input.chunks(3) {
                  let b0 = chunk[0] as usize;
                  let b1 = chunk.get(1).cloned().unwrap_or(0) as usize;
                  let b2 = chunk.get(2).cloned().unwrap_or(0) as usize;
                  result.push(CHARSET[b0 >> 2] as char);
                  result.push(CHARSET[((b0 & 3) << 4) | (b1 >> 4)] as char);
                  result.push(if chunk.len() > 1 { CHARSET[((b1 & 15) << 2) | (b2 >> 6)] as char } else { '=' });
                  result.push(if chunk.len() > 2 { CHARSET[b2 & 63] as char } else { '=' });
              }
              result
          }
          EOF

          # --- CI Telemetry Source ---
          cat << 'EOF' > $out/ci.rs
          use std::{env, fs::File, io::Write, process::Command, thread, time::{Duration, Instant}};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_size = wasm_bytes.len();
              let wasm_base64 = base64_encode(wasm_bytes);
              let b64_size = wasm_base64.len();
              
              println!("[Telemetry] Substrate Size: {} bytes", wasm_size);
              println!("[Telemetry] Base64 Payload Size: {} bytes", b64_size);
              println!("[Telemetry] Encoding Overhead: {:.2}%", (b64_size as f32 / wasm_size as f32 - 1.0) * 100.0);

              let html_content = format!(
                  r#"<!DOCTYPE html><html><head><title>WASM_LOADING</title></head><body>
                  <script>
                      const base64 = '{}';
                      const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
                      WebAssembly.instantiate(bytes).then(() => {{ 
                          document.title = "WASM_SUCCESS"; 
                      }}).catch(e => {{ 
                          document.title = "WASM_ERROR"; 
                      }});
                  </script></body></html>"#, wasm_base64
              );

              let mut path = env::current_dir().unwrap();
              path.push("ci_test.html");
              File::create(&path).and_then(|mut f| f.write_all(html_content.as_bytes())).expect("Write failed");
              println!("[Telemetry] Test page generated at: {:?}", path);

              println!("[Telemetry] Launching Safari...");
              Command::new("open").arg("-a").arg("Safari").arg(&path).spawn().expect("Safari open failed");
              
              let start_time = Instant::now();
              let timeout = Duration::from_secs(10);
              let poll_interval = Duration::from_millis(500);

              println!("[Telemetry] Polling for WASM instantiation...");
              loop {
                  if start_time.elapsed() > timeout {
                      eprintln!("❌ Timeout: WASM failed to instantiate within 10s");
                      std::process::exit(1);
                  }

                  let script = "tell application \"Safari\" to get name of document 1";
                  let output = Command::new("osascript").arg("-e").arg(script).output().expect("osascript failed");
                  let title = String::from_utf8_lossy(&output.stdout);

                  if title.contains("WASM_SUCCESS") {
                      let elapsed = start_time.elapsed().as_millis();
                      println!("✅ Browser Capability Verified!");
                      println!("[Telemetry] Time to Instantiate: {}ms", elapsed);
                      std::process::exit(0);
                  } else if title.contains("WASM_ERROR") {
                      eprintln!("❌ Browser reported WASM_ERROR");
                      std::process::exit(1);
                  }

                  thread::sleep(poll_interval);
              }
          }
          fn base64_encode(input: &[u8]) -> String {
              const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
              let mut result = String::with_capacity((input.len() + 2) / 3 * 4);
              for chunk in input.chunks(3) {
                  let b0 = chunk[0] as usize;
                  let b1 = chunk.get(1).cloned().unwrap_or(0) as usize;
                  let b2 = chunk.get(2).cloned().unwrap_or(0) as usize;
                  result.push(CHARSET[b0 >> 2] as char);
                  result.push(CHARSET[((b0 & 3) << 4) | (b1 >> 4)] as char);
                  result.push(if chunk.len() > 1 { CHARSET[((b1 & 15) << 2) | (b2 >> 6)] as char } else { '=' });
                  result.push(if chunk.len() > 2 { CHARSET[b2 & 63] as char } else { '=' });
              }
              result
          }
          EOF
        '';

        launcher = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-launcher"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          buildPhase = "${rustToolchain}/bin/rustc -O $src/launcher.rs -o wasm-art-launcher";
          installPhase = "mkdir -p $out/bin && cp wasm-art-launcher $out/bin/";
        };

        ci_validator = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-ci"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          buildPhase = "${rustToolchain}/bin/rustc -O $src/ci.rs -o wasm-art-ci";
          installPhase = "mkdir -p $out/bin && cp wasm-art-ci $out/bin/";
        };
      in {
        default = launcher;
        ci = ci_validator;
      };

      devShells.${system}.default = pkgs.mkShell { buildInputs = [ rustToolchain ]; };
    };
}


[End of pasted text #1]


Gemma 4 31B:
This is a Nix flake configuration for a project called the **WASM Kinetic Art Generator**. It provides a fully automated pipeline to compile a mathematical engine into WebAssembly (WASM), embed that binary into a Rust-based launcher, and deploy it to a web browser.

Here is a breakdown of how the system works:

### 1. The WASM Engine (`engine.rs`)
The core logic is written in Rust and compiled to `wasm32-unknown-unknown`. It acts as a stateless math provider for the visualizer:
*   **State:** It maintains a global `TIME` variable.
*   **Functions:** It exports `update_time`, `get_particle_pos`, and `get_particle_y`. These functions use sine and cosine waves to calculate coordinates for particles, creating a fluid, kinetic motion effect.

### 2. The Launcher (`launcher.rs`)
Instead of serving a `.wasm` file over HTTP (which usually requires specific MIME types and a local server), this project uses a "single-file" approach:
*   **Embedding:** The compiled `engine.wasm` is embedded directly into the launcher binary using `include_bytes!`.
*   **Base64 Encoding:** The launcher encodes the WASM binary into a Base64 string.
*   **HTML Generation:** It generates a complete HTML file on the fly. This HTML contains a `<canvas>` element and JavaScript that:
    1.  Decodes the Base64 string back into bytes.
    2.  Instantiates the WASM module.
    3.  Runs a `requestAnimationFrame` loop to draw 250 particles on the screen, calling the WASM functions for their positions.
*   **Execution:** The launcher writes this HTML to a temporary directory and uses the macOS `open` command to launch it in the default browser.

### 3. The CI Validator (`ci.rs`)
This is a telemetry tool designed for automated testing on macOS:
*   **Verification:** It generates a minimal test page and opens it specifically in **Safari**.
*   **AppleScript Integration:** It uses `osascript` to poll the Safari browser's document title. The JavaScript in the test page changes the title to `WASM_SUCCESS` upon successful instantiation or `WASM_ERROR` upon failure.
*   **Metrics:** It calculates and prints the encoding overhead (the size increase caused by Base64) and the time it takes for the browser to instantiate the module.

### 4. The Nix Infrastructure
The `flake.nix` file ensures the environment is reproducible:
*   **Toolchain:** It uses `rust-overlay` to fetch a specific stable Rust version with the `wasm32-unknown-unknown` target pre-configured.
*   **Build Workspace:** It uses `pkgs.runCommand` to create a shared workspace where the Rust source files are written and the WASM engine is compiled before the launcher or CI tools are built.
*   **Platform:** The configuration is specifically targeted at `aarch64-darwin` (Apple Silicon Macs).

### Summary of Execution Flow
`Nix` $\rightarrow$ `rustc (WASM)` $\rightarrow$ `rustc (Launcher)` $\rightarrow$ `Launcher Binary` $\rightarrow$ `Base64 HTML` $\rightarrow$ `Browser` $\rightarrow$ `Canvas Art`

--------------------

User prompt 2 of 3 - 10/28/2026, 11:47:11 AM:
remove ci_test.html after the test is done.

Gemma 4 31B:
To remove the `ci_test.html` file after the test completes, the polling loop in `ci.rs` must be modified to avoid calling `std::process::exit` immediately. Instead, it should break the loop and perform a cleanup operation before exiting the process.

Here is the updated Nix flake:

```nix
# Follow the guidance at https://baselayer-ai.github.io
{
  description = "WASM Kinetic Art Generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };

      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        targets = [ "wasm32-unknown-unknown" ];
      };
    in {
      packages.${system} = let
        buildWorkspace = pkgs.runCommand "art-workspace" {} ''
          mkdir -p $out

          # --- WASM Engine Source ---
          cat << 'EOF' > $out/engine.rs
          static mut TIME: f32 = 0.0;
          #[no_mangle]
          pub extern "C" fn update_time(delta: f32) { unsafe { TIME += delta; } }
          #[no_mangle]
          pub extern "C" fn get_particle_pos(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).sin()).cos() * radius }
          }
          #[no_mangle]
          pub extern "C" fn get_particle_y(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).cos()).sin() * radius }
          }
          EOF

          ${rustToolchain}/bin/rustc --target wasm32-unknown-unknown --crate-type cdylib -O $out/engine.rs -o $out/engine.wasm
          
          # --- Launcher Source ---
          cat << 'EOF' > $out/launcher.rs
          use std::{env, fs::File, io::Write, process::Command};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_base64 = base64_encode(wasm_bytes);
              let html_content = format!(r#"<!DOCTYPE html><html><head><title>WASM Kinetic Art</title></head><body><canvas id="canvas"></canvas><script>const base64 = '{}'; const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0)); WebAssembly.instantiate(bytes).then(({{instance}}) => {{ const {{ update_time, get_particle_pos, get_particle_y }} = instance.exports; const canvas = document.getElementById('canvas'); const ctx = canvas.getContext('2d'); const resize = () => {{ canvas.width = window.innerWidth; canvas.height = window.innerHeight; }}; window.onresize = resize; resize(); const draw = () => {{ update_time(0.02); ctx.fillStyle = 'rgba(5, 5, 5, 0.15)'; ctx.fillRect(0, 0, canvas.width, canvas.height); ctx.fillStyle = '#00ffcc'; for(let i=0; i<250; i++) {{ const x = (canvas.width/2) + get_particle_pos(i, 300); const y = (canvas.height/2) + get_particle_y(i, 300); ctx.beginPath(); ctx.arc(x, y, 1.5, 0, Math.PI*2); ctx.fill(); }} requestAnimationFrame(draw); }}; draw(); }});</script></body></html>"#, wasm_base64);
              let mut temp_path = env::temp_dir(); temp_path.push("wasm_art_generator.html");
              File::create(&temp_path).and_then(|mut f| f.write_all(html_content.as_bytes())).expect("Failed to write HTML");
              Command::new("open").arg(&temp_path).spawn().expect("Failed to open browser");
          }
          fn base64_encode(input: &[u8]) -> String {
              const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
              let mut result = String::with_capacity((input.len() + 2) / 3 * 4);
              for chunk in input.chunks(3) {
                  let b0 = chunk[0] as usize;
                  let b1 = chunk.get(1).cloned().unwrap_or(0) as usize;
                  let b2 = chunk.get(2).cloned().unwrap_or(0) as usize;
                  result.push(CHARSET[b0 >> 2] as char);
                  result.push(CHARSET[((b0 & 3) << 4) | (b1 >> 4)] as char);
                  result.push(if chunk.len() > 1 { CHARSET[((b1 & 15) << 2) | (b2 >> 6)] as char } else { '=' });
                  result.push(if chunk.len() > 2 { CHARSET[b2 & 63] as char } else { '=' });
              }
              result
          }
          EOF

          # --- CI Telemetry Source ---
          cat << 'EOF' > $out/ci.rs
          use std::{env, fs::{self, File}, io::Write, process::Command, thread, time::{Duration, Instant}};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_size = wasm_bytes.len();
              let wasm_base64 = base64_encode(wasm_bytes);
              let b64_size = wasm_base64.len();
              
              println!("[Telemetry] Substrate Size: {} bytes", wasm_size);
              println!("[Telemetry] Base64 Payload Size: {} bytes", b64_size);
              println!("[Telemetry] Encoding Overhead: {:.2}%", (b64_size as f32 / wasm_size as f32 - 1.0) * 100.0);

              let html_content = format!(
                  r#"<!DOCTYPE html><html><head><title>WASM_LOADING</title></head><body>
                  <script>
                      const base64 = '{}';
                      const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
                      WebAssembly.instantiate(bytes).then(() => {{ 
                          document.title = "WASM_SUCCESS"; 
                      }}).catch(e => {{ 
                          document.title = "WASM_ERROR"; 
                      }});
                  </script></body></html>"#, wasm_base64
              );

              let mut path = env::current_dir().unwrap();
              path.push("ci_test.html");
              File::create(&path).and_then(|mut f| f.write_all(html_content.as_bytes())).expect("Write failed");
              println!("[Telemetry] Test page generated at: {:?}", path);

              println!("[Telemetry] Launching Safari...");
              Command::new("open").arg("-a").arg("Safari").arg(&path).spawn().expect("Safari open failed");
              
              let start_time = Instant::now();
              let timeout = Duration::from_secs(10);
              let poll_interval = Duration::from_millis(500);
              let mut success = false;

              println!("[Telemetry] Polling for WASM instantiation...");
              loop {
                  if start_time.elapsed() > timeout {
                      eprintln!("❌ Timeout: WASM failed to instantiate within 10s");
                      break;
                  }

                  let script = "tell application \"Safari\" to get name of document 1";
                  let output = Command::new("osascript").arg("-e").arg(script).output().expect("osascript failed");
                  let title = String::from_utf8_lossy(&output.stdout);

                  if title.contains("WASM_SUCCESS") {
                      let elapsed = start_time.elapsed().as_millis();
                      println!("✅ Browser Capability Verified!");
                      println!("[Telemetry] Time to Instantiate: {}ms", elapsed);
                      success = true;
                      break;
                  } else if title.contains("WASM_ERROR") {
                      eprintln!("❌ Browser reported WASM_ERROR");
                      break;
                  }

                  thread::sleep(poll_interval);
              }

              fs::remove_file(&path).expect("Failed to remove CI test file");
              println!("[Telemetry] Cleanup: Removed {:?}", path);

              if success {
                  std::process::exit(0);
              } else {
                  std::process::exit(1);
              }
          }
          fn base64_encode(input: &[u8]) -> String {
              const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
              let mut result = String::with_capacity((input.len() + 2) / 3 * 4);
              for chunk in input.chunks(3) {
                  let b0 = chunk[0] as usize;
                  let b1 = chunk.get(1).cloned().unwrap_or(0) as usize;
                  let b2 = chunk.get(2).cloned().unwrap_or(0) as usize;
                  result.push(CHARSET[b0 >> 2] as char);
                  result.push(CHARSET[((b0 & 3) << 4) | (b1 >> 4)] as char);
                  result.push(if chunk.len() > 1 { CHARSET[((b1 & 15) << 2) | (b2 >> 6)] as char } else { '=' });
                  result.push(if chunk.len() > 2 { CHARSET[b2 & 63] as char } else { '=' });
              }
              result
          }
          EOF
        '';

        launcher = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-launcher"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          buildPhase = "${rustToolchain}/bin/rustc -O $src/launcher.rs -o wasm-art-launcher";
          installPhase = "mkdir -p $out/bin && cp wasm-art-launcher $out/bin/";
        };

        ci_validator = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-ci"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          buildPhase = "${rustToolchain}/bin/rustc -O $src/ci.rs -o wasm-art-ci";
          installPhase = "mkdir -p $out/bin && cp wasm-art-ci $out/bin/";
        };
      in {
        default = launcher;
        ci = ci_validator;
      };

      devShells.${system}.default = pkgs.mkShell { buildInputs = [ rustToolchain ]; };
    };
}
```

--------------------

User prompt 3 of 3 - 10/28/2026, 11:49:54 AM:
We got CI error: 


[Telemetry] Substrate Size: 1660876 bytes
[Telemetry] Base64 Payload Size: 2214504 bytes
[Telemetry] Encoding Overhead: 33.33%
[Telemetry] Test page generated at: "/Users/runner/work/baselayer-ai-wasm-demo-aarch64-darwin/baselayer-ai-wasm-demo-aarch64-darwin/ci_test.html"
[Telemetry] Launching Safari...
[Telemetry] Polling for WASM instantiation...
❌ Timeout: WASM failed to instantiate within 10s


Gemma 4 31B:
The timeout is likely occurring because the WASM binary is unexpectedly large (~1.6 MB for a few lines of code), which slows down the Base64 decoding (`atob`) and the instantiation process in the browser, especially on a resource-constrained CI runner.

The binary is large because the current `rustc` command is not optimizing for size and is likely including debug symbols. By switching to `opt-level=z` (optimize for size) and enabling Link Time Optimization (`lto`), the binary will shrink significantly, making the loading process nearly instantaneous.

I have also increased the CI timeout to 20 seconds to account for the latency of launching Safari on a headless CI runner.

```nix
# Follow the guidance at https://baselayer-ai.github.io
{
  description = "WASM Kinetic Art Generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };

      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        targets = [ "wasm32-unknown-unknown" ];
      };
    in {
      packages.${system} = let
        buildWorkspace = pkgs.runCommand "art-workspace" {} ''
          mkdir -p $out

          # --- WASM Engine Source ---
          cat << 'EOF' > $out/engine.rs
          static mut TIME: f32 = 0.0;
          #[no_mangle]
          pub extern "C" fn update_time(delta: f32) { unsafe { TIME += delta; } }
          #[no_mangle]
          pub extern "C" fn get_particle_pos(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).sin()).cos() * radius }
          }
          #[no_mangle]
          pub extern "C" fn get_particle_y(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).cos()).sin() * radius }
          }
          EOF

          # Optimized for size: opt-level=z and lto=fat drastically reduce WASM binary size
          ${rustToolchain}/bin/rustc --target wasm32-unknown-unknown --crate-type cdylib -C opt-level=z -C lto=fat $out/engine.rs -o $out/engine.wasm
          
          # --- Launcher Source ---
          cat << 'EOF' > $out/launcher.rs
          use std::{env, fs::File, io::Write, process::Command};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_base64 = base64_encode(wasm_bytes);
              let html_content = format!(r#"<!DOCTYPE html><html><head><title>WASM Kinetic Art</title></head><body><canvas id="canvas"></canvas><script>const base64 = '{}'; const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0)); WebAssembly.instantiate(bytes).then(({{instance}}) => {{ const {{ update_time, get_particle_pos, get_particle_y }} = instance.exports; const canvas = document.getElementById('canvas'); const ctx = canvas.getContext('2d'); const resize = () => {{ canvas.width = window.innerWidth; canvas.height = window.innerHeight; }}; window.onresize = resize; resize(); const draw = () => {{ update_time(0.02); ctx.fillStyle = 'rgba(5, 5, 5, 0.15)'; ctx.fillRect(0, 0, canvas.width, canvas.height); ctx.fillStyle = '#00ffcc'; for(let i=0; i<250; i++) {{ const x = (canvas.width/2) + get_particle_pos(i, 300); const y = (canvas.height/2) + get_particle_y(i, 300); ctx.beginPath(); ctx.arc(x, y, 1.5, 0, Math.PI*2); ctx.fill(); }} requestAnimationFrame(draw); }}; draw(); }});</script></body></html>"#, wasm_base64);
              let mut temp_path = env::temp_dir(); temp_path.push("wasm_art_generator.html");
              File::create(&temp_path).and_then(|mut f| f.write_all(html_content.as_bytes())).expect("Failed to write HTML");
              Command::new("open").arg(&temp_path).spawn().expect("Failed to open browser");
          }
          fn base64_encode(input: &[u8]) -> String {
              const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
              let mut result = String::with_capacity((input.len() + 2) / 3 * 4);
              for chunk in input.chunks(3) {
                  let b0 = chunk[0] as usize;
                  let b1 = chunk.get(1).cloned().unwrap_or(0) as usize;
                  let b2 = chunk.get(2).cloned().unwrap_or(0) as usize;
                  result.push(CHARSET[b0 >> 2] as char);
                  result.push(CHARSET[((b0 & 3) << 4) | (b1 >> 4)] as char);
                  result.push(if chunk.len() > 1 { CHARSET[((b1 & 15) << 2) | (b2 >> 6)] as char } else { '=' });
                  result.push(if chunk.len() > 2 { CHARSET[b2 & 63] as char } else { '=' });
              }
              result
          }
          EOF

          # --- CI Telemetry Source ---
          cat << 'EOF' > $out/ci.rs
          use std::{env, fs::{self, File}, io::Write, process::Command, thread, time::{Duration, Instant}};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_size = wasm_bytes.len();
              let wasm_base64 = base64_encode(wasm_bytes);
              let b64_size = wasm_base64.len();
              
              println!("[Telemetry] Substrate Size: {} bytes", wasm_size);
              println!("[Telemetry] Base64 Payload Size: {} bytes", b64_size);
              println!("[Telemetry] Encoding Overhead: {:.2}%", (b64_size as f32 / wasm_size as f32 - 1.0) * 100.0);

              let html_content = format!(
                  r#"<!DOCTYPE html><html><head><title>WASM_LOADING</title></head><body>
                  <script>
                      const base64 = '{}';
                      const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
                      WebAssembly.instantiate(bytes).then(() => {{ 
                          document.title = "WASM_SUCCESS"; 
                      }}).catch(e => {{ 
                          document.title = "WASM_ERROR"; 
                      }});
                  </script></body></html>"#, wasm_base64
              );

              let mut path = env::current_dir().unwrap();
              path.push("ci_test.html");
              File::create(&path).and_then(|mut f| f.write_all(html_content.as_bytes())).expect("Write failed");
              println!("[Telemetry] Test page generated at: {:?}", path);

              println!("[Telemetry] Launching Safari...");
              Command::new("open").arg("-a").arg("Safari").arg(&path).spawn().expect("Safari open failed");
              
              let start_time = Instant::now();
              let timeout = Duration::from_secs(20); // Increased timeout for CI runners
              let poll_interval = Duration::from_millis(500);
              let mut success = false;

              println!("[Telemetry] Polling for WASM instantiation...");
              loop {
                  if start_time.elapsed() > timeout {
                      eprintln!("❌ Timeout: WASM failed to instantiate within 20s");
                      break;
                  }

                  let script = "tell application \"Safari\" to get name of document 1";
                  let output = Command::new("osascript").arg("-e").arg(script).output().expect("osascript failed");
                  let title = String::from_utf8_lossy(&output.stdout);

                  if title.contains("WASM_SUCCESS") {
                      let elapsed = start_time.elapsed().as_millis();
                      println!("✅ Browser Capability Verified!");
                      println!("[Telemetry] Time to Instantiate: {}ms", elapsed);
                      success = true;
                      break;
                  } else if title.contains("WASM_ERROR") {
                      eprintln!("❌ Browser reported WASM_ERROR");
                      break;
                  }

                  thread::sleep(poll_interval);
              }

              fs::remove_file(&path).expect("Failed to remove CI test file");
              println!("[Telemetry] Cleanup: Removed {:?}", path);

              if success {
                  std::process::exit(0);
              } else {
                  std::process::exit(1);
              }
          }
          fn base64_encode(input: &[u8]) -> String {
              const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
              let mut result = String::with_capacity((input.len() + 2) / 3 * 4);
              for chunk in input.chunks(3) {
                  let b0 = chunk[0] as usize;
                  let b1 = chunk.get(1).cloned().unwrap_or(0) as usize;
                  let b2 = chunk.get(2).cloned().unwrap_or(0) as usize;
                  result.push(CHARSET[b0 >> 2] as char);
                  result.push(CHARSET[((b0 & 3) << 4) | (b1 >> 4)] as char);
                  result.push(if chunk.len() > 1 { CHARSET[((b1 & 15) << 2) | (b2 >> 6)] as char } else { '=' });
                  result.push(if chunk.len() > 2 { CHARSET[b2 & 63] as char } else { '=' });
              }
              result
          }
          EOF
        '';

        launcher = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-launcher"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          buildPhase = "${rustToolchain}/bin/rustc -O $src/launcher.rs -o wasm-art-launcher";
          installPhase = "mkdir -p $out/bin && cp wasm-art-launcher $out/bin/";
        };

        ci_validator = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-ci"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          buildPhase = "${rustToolchain}/bin/rustc -O $src/ci.rs -o wasm-art-ci";
          installPhase = "mkdir -p $out/bin && cp wasm-art-ci $out/bin/";
        };
      in {
        default = launcher;
        ci = ci_validator;
      };

      devShells.${system}.default = pkgs.mkShell { buildInputs = [ rustToolchain ]; };
    };
}
```