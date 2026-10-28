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
          pub extern "C" fn update_time(delta: f32) {
              unsafe { TIME += delta; }
          }

          #[no_mangle]
          pub extern "C" fn get_particle_pos(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).sin()).cos() * radius }
          }

          #[no_mangle]
          pub extern "C" fn get_particle_y(index: f32, radius: f32) -> f32 {
              unsafe { (radius * (index * 0.1 + TIME * 0.5).cos()).sin() * radius }
          }
          EOF

          # Compile the WASM substrate
          ${rustToolchain}/bin/rustc --target wasm32-unknown-unknown --crate-type cdylib -O $out/engine.rs -o $out/engine.wasm
          
          # --- Launcher Source ---
          cat << 'EOF' > $out/launcher.rs
          use std::{env, fs::File, io::Write, process::Command};

          fn main() {
              let wasm_bytes = include_bytes!("engine.wasm");
              let wasm_base64 = base64_encode(wasm_bytes);

              println!("🎨 Generating self-contained WASM art page...");
              
              let html_content = format!(
                  r#"<!DOCTYPE html>
                  <html>
                  <head>
                      <title>WASM Kinetic Art</title>
                      <style>
                          body {{ margin: 0; background: #050505; overflow: hidden; }}
                      </style>
                  </head>
                  <body>
                      <canvas id="canvas"></canvas>
                      <script>
                          const base64 = '{}';
                          const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
                          
                          WebAssembly.instantiate(bytes).then(({{instance}}) => {{
                              const {{ update_time, get_particle_pos, get_particle_y }} = instance.exports;
                              const canvas = document.getElementById('canvas');
                              const ctx = canvas.getContext('2d');
                              
                              const resize = () => {{
                                  canvas.width = window.innerWidth;
                                  canvas.height = window.innerHeight;
                              }};
                              window.onresize = resize;
                              resize();

                              const draw = () => {{
                                  update_time(0.02);
                                  ctx.fillStyle = 'rgba(5, 5, 5, 0.15)';
                                  ctx.fillRect(0, 0, canvas.width, canvas.height);
                                  ctx.fillStyle = '#00ffcc';
                                  for(let i=0; i<250; i++) {{
                                      const x = (canvas.width/2) + get_particle_pos(i, 300);
                                      const y = (canvas.height/2) + get_particle_y(i, 300);
                                      ctx.beginPath(); ctx.arc(x, y, 1.5, 0, Math.PI*2); ctx.fill();
                                  }}
                                  requestAnimationFrame(draw);
                              }};
                              draw();
                          }});
                      </script>
                  </body>
                  </html>"#,
                  wasm_base64
              );

              let mut temp_path = env::temp_dir();
              temp_path.push("wasm_art_generator.html");
              
              File::create(&temp_path).and_then(|mut f| f.write_all(html_content.as_bytes()))
                  .expect("Failed to write HTML to temp directory");

              println!("🚀 Opening browser to: {:?}", temp_path);
              Command::new("open").arg(&temp_path).spawn().expect("Failed to open browser");
              println!("✨ Animation active. You can close this terminal.");
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

        app = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-launcher";
          version = "1.3.0";
          src = buildWorkspace;
          nativeBuildInputs = [ rustToolchain ];
          
          buildPhase = ''
            ${rustToolchain}/bin/rustc -O $src/launcher.rs -o wasm-art-launcher
            
            # Generate README.md inside the build folder
            cat << 'EOF' > README.md
            # WASM Kinetic Art Launcher
            
            This tool demonstrates a monolithic Rust-driven WASM substrate. 
            
            ## How it works
            1. **WASM Engine**: A Rust-compiled WebAssembly module handles the trigonometry for particle orbits.
            2. **Launcher**: A native macOS binary that bakes the WASM binary into its own executable.
            3. **Deployment**: The launcher generates a temporary HTML file containing the WASM as a Base64 string and opens it in the default browser.
            
            ## Usage
            Simply run the binary to launch the visualization in your default web browser.
            EOF
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp wasm-art-launcher $out/bin/
            cp README.md $out/
          '';
        };
      in {
        default = app;
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ rustToolchain ];
      };
    };
}

