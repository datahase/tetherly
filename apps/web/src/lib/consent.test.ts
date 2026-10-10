import { test } from "node:test";
import assert from "node:assert/strict";
import { needsConsent } from "./consent.ts";

test("opt-in regions and unknown countries need consent", () => {
  for (const c of ["DE", "fr", "GB", "NO", "CH", null, undefined, ""]) assert.equal(needsConsent(c), true, String(c));
  for (const c of ["US", "IN", "JP", "BR"]) assert.equal(needsConsent(c), false, c);
});
