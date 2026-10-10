import { test } from "node:test";
import assert from "node:assert/strict";
import { absoluteLinks, parseBlocks, plainText } from "./markdown.ts";

test("parses headings, paragraphs and lists", () => {
  assert.deepEqual(parseBlocks("## Title\n\nOne\nline.\n\n- a\n- b\n\n1. x\n2. y\n\n### Sub"), [
    { type: "h2", text: "Title" },
    { type: "p", text: "One line." },
    { type: "ul", items: ["a", "b"] },
    { type: "ol", items: ["x", "y"] },
    { type: "h3", text: "Sub" },
  ]);
});

test("plain text and absolute links", () => {
  assert.equal(plainText("See **the** [guide](/setup).\n\n- one"), "See the guide.\n• one");
  assert.equal(absoluteLinks("[a](/x) [b](https://y.z)", "https://t.link"), "[a](https://t.link/x) [b](https://y.z)");
});
