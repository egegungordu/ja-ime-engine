import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { copyFileSync, existsSync, mkdirSync } from "fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const wasmPath = join(__dirname, "..", "..", "zig-out", "bin", "libjaime.wasm");
const destPath = join(__dirname, "public", "libjaime.wasm");

// Create public directory if it doesn't exist
if (!existsSync(join(__dirname, "public"))) {
  mkdirSync(join(__dirname, "public"));
}

// Copy the file
copyFileSync(wasmPath, destPath);
console.log("Copied WASM file to public folder");
