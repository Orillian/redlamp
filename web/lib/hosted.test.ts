import assert from "node:assert/strict";
import { test } from "node:test";
import { hostedFiles } from "./hosted.ts";

test("without the variables, nothing is hosted", () => {
  assert.deepEqual(hostedFiles({}), []);
});

test("each numbered pair is served at its path from where it's kept", () => {
  const env = {
    HOSTED_1_PATH: "/files/one.bin",
    HOSTED_1_URL: "https://store.example/one",
    HOSTED_2_PATH: "/files/two.key",
    HOSTED_2_URL: "https://store.example/two",
    HOSTED_4_PATH: "/files/four.bin",
    HOSTED_4_URL: "https://store.example/four",
  };
  assert.deepEqual(hostedFiles(env), [
    { source: "/files/one.bin", destination: "https://store.example/one" },
    { source: "/files/two.key", destination: "https://store.example/two" },
  ]);
});

test("a pair half set, a pattern for a path or a plain http address stops the build", () => {
  assert.throws(() => hostedFiles({ HOSTED_1_PATH: "/files/one.bin" }), /HOSTED_1_URL/);
  assert.throws(() => hostedFiles({ HOSTED_1_URL: "https://store.example/one" }), /HOSTED_1_PATH/);
  const url = "https://store.example/one";
  assert.throws(() => hostedFiles({ HOSTED_1_PATH: "/files/:name", HOSTED_1_URL: url }), /HOSTED_1_PATH/);
  assert.throws(() => hostedFiles({ HOSTED_1_PATH: "files/one.bin", HOSTED_1_URL: url }), /HOSTED_1_PATH/);
  const plain = { HOSTED_1_PATH: "/files/one.bin", HOSTED_1_URL: "http://store.example/one" };
  assert.throws(() => hostedFiles(plain), /HOSTED_1_URL/);
});
