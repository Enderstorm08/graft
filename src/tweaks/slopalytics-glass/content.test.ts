import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const source = readFileSync(new URL("./content.js", import.meta.url), "utf8");
function harness(hostname = "slopalytics.com") {
  const attributes = new Set<string>();
  const styles = new Map<string, { id: string; textContent: string; remove(): void }>();
  let getCallback: ((stored: object) => void) | undefined;
  let listener: ((changes: object, area: string) => void) | undefined;
  const root = { hasAttribute: (a: string) => attributes.has(a), setAttribute: (a: string) => attributes.add(a), removeAttribute: (a: string) => attributes.delete(a) };
  const runtime: { id?: string; lastError?: object } = { id: "test-extension" };
  const window = {}; Object.assign(window, { self: window, top: window });
  vm.runInNewContext(source, {
    window, location: { hostname }, document: {
      documentElement: root,
      head: { appendChild: (node: {id: string; textContent: string; remove(): void}) => styles.set(node.id, node) },
      getElementById: (id: string) => styles.get(id),
      createElement: () => ({ id: "", textContent: "", remove() { styles.delete(this.id); } }),
    },
    chrome: { runtime, storage: { sync: { get: (_defaults: object, cb: (stored: object) => void) => { getCallback = cb; } }, onChanged: { addListener: (cb: typeof listener) => { listener = cb; } } } },
  });
  return { attributes, styles, runtime, initial: (value: boolean) => getCallback?.({ slopalyticsGlassEnabled: value }), change: (value: boolean, area = "sync") => listener?.({ slopalyticsGlassEnabled: { newValue: value } }, area) };
}

describe("Slopalytics Glass lifecycle", () => {
  it("restores the original DOM styling on disable and does not duplicate styles", () => {
    const h = harness(); h.initial(true); h.change(true);
    expect(h.styles.size).toBe(1);
    expect(h.attributes.has("data-graft-slopalytics-glass")).toBe(true);
    h.change(false);
    expect(h.styles.size).toBe(0); expect(h.attributes.size).toBe(0);
    h.change(true); expect(h.styles.size).toBe(1);
  });
  it("does not overwrite a newer toggle with the initial asynchronous read", () => {
    const h = harness(); h.change(true); h.initial(false); expect(h.styles.size).toBe(1);
  });
  it("stays off by default and ignores unrelated storage areas", () => {
    const h = harness(); h.initial(false); h.change(true, "local"); expect(h.styles.size).toBe(0);
  });
  it("does not inject on lookalike or unrelated hosts", () => {
    for (const host of ["slopalytics.com.evil.test", "example.com"]) {
      const h = harness(host); h.initial(true); h.change(true); expect(h.styles.size).toBe(0);
    }
  });
  it("cleans up without throwing if the extension context disappears", () => {
    const h = harness(); h.initial(true); delete h.runtime.id;
    expect(() => h.change(true)).not.toThrow(); expect(h.styles.size).toBe(0);
  });
});
