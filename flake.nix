{
  description = "WASM Kinetic Art Generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    # rust-overlay removed
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
      };
    in {
      packages.${system} = let
        buildWorkspace = pkgs.runCommand "art-workspace" {
          nativeBuildInputs = [ pkgs.coreutils pkgs.rustc pkgs.lld];
        } ''
          mkdir -p $out

          # --- WASM Engine Source ---
          cat << 'EOF' > $out/engine.rs
          static mut TIME: f32 = 0.0;
          const WIDTH: usize = 1280;
          const HEIGHT: usize = 720;
          static mut BUFFER: [u32; WIDTH * HEIGHT] = [0xFF050505; WIDTH * HEIGHT];

          #[no_mangle]
          pub extern "C" fn get_buffer_ptr() -> *const u32 {
              unsafe { std::ptr::addr_of!(BUFFER) as *const u32 }
          }

          #[no_mangle]
          pub extern "C" fn render_frame() {
              unsafe {
                  TIME += 0.015;
                  let buffer_ptr = std::ptr::addr_of_mut!(BUFFER) as *mut u32;
                  for offset in 0..(WIDTH * HEIGHT) {
                      let p = *buffer_ptr.add(offset);
                      let r = ((p & 0xFF) as f32 * 0.92) as u32;
                      let g = (((p >> 8) & 0xFF) as f32 * 0.92) as u32;
                      let b = (((p >> 16) & 0xFF) as f32 * 0.92) as u32;
                      *buffer_ptr.add(offset) = r | (g << 8) | (b << 16) | 0xFF000000;
                  }

                  let cx = (WIDTH / 2) as f32;
                  let cy = (HEIGHT / 2) as f32;
                  let r_outer = 240.0;
                  let r_inner = 150.0;
                  let d = 130.0 + TIME.sin() * 60.0;

                  for i in 0..1000 {
                      let t = (i as f32) * 0.05 + TIME;
                      let ratio = (r_outer - r_inner) / r_inner;
                      let base_x = (r_outer - r_inner) * t.cos() + d * (ratio * t).cos();
                      let base_y = (r_outer - r_inner) * t.sin() - d * (ratio * t).sin();
                      let wave_mod_x = (t * 7.0 + TIME * 2.5).sin() * 40.0;
                      let wave_mod_y = (t * 5.0 - TIME * 3.1).cos() * 40.0;
                      let px = (cx + base_x + wave_mod_x) as i32;
                      let py = (cy + base_y + wave_mod_y) as i32;
                      let r_color = ((t.sin() * 127.0) + 128.0) as u32;
                      let g_color = (((t + 2.0).sin() * 127.0) + 128.0) as u32;
                      let b_color = (((TIME * 0.5).cos() * 100.0) + 155.0) as u32;
                      let packed_color = r_color | (g_color << 8) | (b_color << 16) | 0xFF000000;

                      for dx in 0..2 {
                          for dy in 0..2 {
                              let target_x = px + dx;
                              let target_y = py + dy;
                              if target_x >= 0 && target_x < WIDTH as i32 && target_y >= 0 && target_y < HEIGHT as i32 {
                                  let offset = (target_y as usize * WIDTH) + target_x as usize;
                                  *buffer_ptr.add(offset) = packed_color;
                              }
                          }
                      }
                  }
              }
          }
          EOF

          # Use the standard rustc binary
          ${pkgs.rustc}/bin/rustc --target wasm32-unknown-unknown --crate-type cdylib -C opt-level=z -C lto=fat $out/engine.rs -o $out/engine.wasm
          
          WASM_BASE64=$(base64 $out/engine.wasm | tr -d '\n')

          # --- Launcher Source ---
          cat << EOF > $out/launcher.rs
          use std::{io::{Read, Write}, net::TcpListener, process::Command};
          fn main() {
              let html_content = "<!DOCTYPE html><html><head><title>WASM Kinetic Art</title><style>html,body{margin:0;padding:0;overflow:hidden;background:#050505;width:100%;height:100%;}canvas{width:100vw;height:100vh;display:block;object-fit:cover;}</style></head><body><canvas id=\"canvas\" width=\"1280\" height=\"720\"></canvas><script>const base64 = '$WASM_BASE64'; const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0)); WebAssembly.instantiate(bytes).then(({instance}) => { const { memory, get_buffer_ptr, render_frame } = instance.exports; const canvas = document.getElementById('canvas'); const ctx = canvas.getContext('2d'); const imgData = ctx.createImageData(1280, 720); const u8Buffer = new Uint8Array(memory.buffer, get_buffer_ptr(), 1280 * 720 * 4); const draw = () => { render_frame(); imgData.data.set(u8Buffer); ctx.putImageData(imgData, 0, 0); requestAnimationFrame(draw); }; draw(); });</script></body></html>";
              
              let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", html_content.len(), html_content);
              let favicon_404 = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
              
              let listener = TcpListener::bind("127.0.0.1:8888").expect("Failed to bind to port 8888");
              println!("[Server] In-memory server running at http://127.0.0.1:8888");

              Command::new("open").arg("http://127.0.0.1:8888").spawn().expect("Failed to open browser");

              for stream in listener.incoming() {
                  if let Ok(mut stream) = stream {
                      let mut buffer = [0; 1024];
                      if let Ok(bytes_read) = stream.read(&mut buffer) {
                          let request_str = String::from_utf8_lossy(&buffer[..bytes_read]);
                          if request_str.contains("GET /favicon.ico") {
                              let _ = stream.write_all(favicon_404.as_bytes());
                          } else {
                              let _ = stream.write_all(response.as_bytes());
                          }
                          let _ = stream.flush();
                      }
                  }
              }
          }
          EOF
        '';

        launcher = pkgs.stdenv.mkDerivation {
          pname = "wasm-art-launcher"; version = "1.3.0"; src = buildWorkspace;
          nativeBuildInputs = [ pkgs.rustc ];
          buildPhase = "${pkgs.rustc}/bin/rustc -O launcher.rs -o wasm-art-launcher";
          installPhase = "mkdir -p $out/bin && cp wasm-art-launcher $out/bin/";
        };

      in {
        default = launcher;
      };

      devShells.${system}.default = pkgs.mkShell { buildInputs = [ pkgs.rustc ]; };
    };
}

