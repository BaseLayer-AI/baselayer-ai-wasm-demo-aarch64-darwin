# Follow the guidance at https://github.io
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
          use std::{io::Write, net::TcpListener, process::Command};
          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_base64 = base64_encode(wasm_bytes);
              let html_content = format!(r#"<!DOCTYPE html><html><head><title>WASM Kinetic Art</title></head><body style='margin:0;'><canvas id="canvas"></canvas><script>const base64 = '{}'; const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0)); WebAssembly.instantiate(bytes).then(({{instance}}) => {{ const {{ update_time, get_particle_pos, get_particle_y }} = instance.exports; const canvas = document.getElementById('canvas'); const ctx = canvas.getContext('2d'); const resize = () => {{ canvas.width = window.innerWidth; canvas.height = window.innerHeight; }}; window.onresize = resize; resize(); const draw = () => {{ update_time(0.02); ctx.fillStyle = 'rgba(5, 5, 5, 0.15)'; ctx.fillRect(0, 0, canvas.width, canvas.height); ctx.fillStyle = '#00ffcc'; for(let i=0; i<250; i++) {{ const x = (canvas.width/2) + get_particle_pos(i, 300); const y = (canvas.height/2) + get_particle_y(i, 300); ctx.beginPath(); ctx.arc(x, y, 1.5, 0, Math.PI*2); ctx.fill(); }} requestAnimationFrame(draw); }}; draw(); }});</script></body></html>"#, wasm_base64);
              
              let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\n\r\n{}", html_content.len(), html_content);
              let listener = TcpListener::bind("127.0.0.1:8888").expect("Failed to bind to port 8888");
              println!("[Server] In-memory server running at http://127.0.0.1:8888");

              Command::new("open").arg("http://127.0.0.1:8888").spawn().expect("Failed to open browser");

              for stream in listener.incoming() {
                  if let Ok(mut stream) = stream {
                      let _ = stream.write_all(response.as_bytes());
                      let _ = stream.flush();
                  }
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

          # --- CI Telemetry Source ---
          cat << 'EOF' > $out/ci.rs
          use std::{io::Write, net::TcpListener, process::Command, thread, time::{Duration, Instant}};
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

              let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\n\r\n{}", html_content.len(), html_content);
              let listener = TcpListener::bind("127.0.0.1:8888").expect("Failed to bind to port 8888");
              listener.set_nonblocking(true).expect("Cannot set non-blocking");

              println!("[Telemetry] Launching Safari targeting http://127.0.0.1:8888 ...");
              Command::new("open").arg("-a").arg("Safari").arg("http://127.0.0.1:8888").spawn().expect("Safari open failed");
              
              let start_time = Instant::now();
              let timeout = Duration::from_secs(20);
              let poll_interval = Duration::from_millis(500);
              let mut success = false;

              println!("[Telemetry] Polling for WASM instantiation via HTTP and osascript...");
              loop {
                  if start_time.elapsed() > timeout {
                      eprintln!("❌ Timeout: WASM failed to instantiate within 20s");
                      break;
                  }

                  // Non-blocking serve for any incoming connections from Safari
                  if let Ok((mut stream, _)) = listener.accept() {
                      let _ = stream.write_all(response.as_bytes());
                      let _ = stream.flush();
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

