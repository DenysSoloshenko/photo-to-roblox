import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
const root = new URL("../public/cases/springer-park/", import.meta.url);
const read = name => readFileSync(new URL(name, root));

test("public case includes usable PNG previews", () => {
  for (const name of ["overview.png", "street.png"]) {
    const image = read(name);
    assert.equal(image.subarray(1, 4).toString(), "PNG");
    assert.ok(image.readUInt32BE(16) >= 1280);
    assert.ok(image.readUInt32BE(20) >= 600);
  }
});
test("case source and methods carry open-data attribution", () => {
  for (const name of ["source.json", "scene.json", "plan.svg", "LICENSE.md"]) {
    assert.match(read(name).toString(), /OpenStreetMap/);
    assert.match(read(name).toString(), /ODbL|odbl/);
  }
  const source = JSON.parse(read("source.json"));
  assert.ok(source.features.every(f => !Object.hasOwn(f, "user") && !Object.hasOwn(f, "uid")));
});
test("case metrics reflect the actual geometry", () => {
  const scene = JSON.parse(read("scene.json"));
  const metrics = JSON.parse(read("metrics.json"));
  assert.equal(scene.parts.length, metrics.part_count);
  assert.equal(metrics.building_count, 20);
  assert.deepEqual(metrics.area_m, [440, 290]);
});
test("walkthrough is an MP4 with local captions, not a missing placeholder", () => {
  const video = read("SceneFoundry_Case_Walkthrough.mp4");
  assert.equal(video.subarray(4, 8).toString(), "ftyp");
  assert.ok(video.length > 100_000 && video.length < 30_000_000);
  const captions = read("walkthrough.en.vtt").toString();
  assert.ok(captions.startsWith("WEBVTT"));
  assert.match(captions, /00:01:00\.000/);
});
test("downloadable Roblox place is substantial and script-free", () => {
  assert.ok(statSync(new URL("Springer_Park_Open_Data.rbxlx", root)).size > 1_000_000);
  assert.doesNotMatch(read("Springer_Park_Open_Data.rbxlx").toString(), /class=['"](?:Script|LocalScript|ModuleScript)['"]/);
});
