#!/usr/bin/env node
// Renders docs/demo.svg frame by frame in headless Chrome and encodes two looping animations:
//   docs/demo.webp  1200x750, lossless
//   docs/demo.gif   900x563, for places that don't show WebP
//
// Needs Google Chrome, Node 22+, img2webp (brew install webp) and ffmpeg.
// Run: node scripts/make-demo-anim.mjs

import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const svg = join(root, "docs/demo.svg");
const out = join(root, "docs/demo.webp");
const gif = join(root, "docs/demo.gif");
const GIF_WIDTH = 900;

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9333;
const DURATION = 12;   // seconds, matches DURATION in make-demo-svg.py
const FPS = 20;
const SCALE = 1.5;     // 800x500 SVG becomes 1200x750 frames

const work = mkdtempSync(join(tmpdir(), "tilty-webp-"));
const chrome = spawn(CHROME, [
  "--headless=new", "--disable-gpu", "--hide-scrollbars",
  `--remote-debugging-port=${PORT}`, `--user-data-dir=${join(work, "profile")}`,
  "about:blank",
], { stdio: "ignore" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function devtoolsPage() {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: "PUT" });
      if (res.ok) return (await res.json()).webSocketDebuggerUrl;
    } catch {}
    await sleep(200);
  }
  throw new Error("Chrome did not start");
}

try {
  const ws = new WebSocket(await devtoolsPage());
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    }
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const n = ++id;
    pending.set(n, { resolve, reject });
    ws.send(JSON.stringify({ id: n, method, params }));
  });

  await send("Emulation.setDeviceMetricsOverride", { width: 800, height: 500, deviceScaleFactor: SCALE, mobile: false });
  await send("Page.enable");
  await send("Page.navigate", { url: `file://${svg}` });
  await sleep(1000);
  await send("Runtime.evaluate", { expression: "document.documentElement.pauseAnimations()" });

  const frames = Math.round(DURATION * FPS);
  for (let i = 0; i < frames; i++) {
    await send("Runtime.evaluate", { expression: `document.documentElement.setCurrentTime(${(i / FPS).toFixed(4)})` });
    const { data } = await send("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(work, `f${String(i).padStart(4, "0")}.png`), Buffer.from(data, "base64"));
  }
  ws.close();

  const args = ["-loop", "0", "-lossless", "-q", "100", "-m", "6", "-d", String(Math.round(1000 / FPS))];
  for (let i = 0; i < frames; i++) args.push(join(work, `f${String(i).padStart(4, "0")}.png`));
  args.push("-o", out);
  execFileSync("img2webp", args, { stdio: "inherit" });
  console.log(`Wrote ${out} (${frames} frames at ${FPS} fps)`);

  // GIF: one shared 256 color palette, light ordered dithering for the wallpaper gradient.
  execFileSync("ffmpeg", [
    "-v", "error", "-y", "-framerate", String(FPS), "-i", join(work, "f%04d.png"),
    "-vf", `scale=${GIF_WIDTH}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle`,
    "-loop", "0", gif,
  ], { stdio: "inherit" });
  console.log(`Wrote ${gif}`);
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(work, { recursive: true, force: true });
}
