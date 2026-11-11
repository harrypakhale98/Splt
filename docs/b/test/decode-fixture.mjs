// Checks the balance link page against links the app produced.
//
//   node docs/b/test/decode-fixture.mjs           run the checks
//   node docs/b/test/decode-fixture.mjs --pin-csp  rewrite the page's script hash after editing it
//
// fixture.txt and fixture-large.txt are written by BalanceLinkTests in SpltTests, so the Swift encoder
// and the page's decoder have to agree. Needs Node 18 or later.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { deflateRawSync } from "node:zlib";

const here = dirname(fileURLToPath(import.meta.url));
const pagePath = join(here, "..", "index.html");
let page = readFileSync(pagePath, "utf8");

const scriptMatch = page.match(/<script>([\s\S]*?)<\/script>/);
assert.ok(scriptMatch, "the page has one inline script");
const script = scriptMatch[1];
const hash = createHash("sha256").update(script, "utf8").digest("base64");

if (process.argv.includes("--pin-csp")) {
  page = page.replace(/script-src 'sha256-[^']*'/, `script-src 'sha256-${hash}'`);
  writeFileSync(pagePath, page);
  console.log(`pinned script hash sha256-${hash}`);
  process.exit(0);
}

let failures = 0;
async function check(name, body) {
  try {
    await body();
    console.log(`ok   ${name}`);
  } catch (error) {
    failures += 1;
    console.log(`FAIL ${name}\n     ${error.message}`);
  }
}

// MARK: The page itself

await check("the CSP pins the inline script and allows nothing from other hosts", () => {
  const csp = page.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
  assert.ok(csp.includes(`script-src 'sha256-${hash}'`), "script hash is stale: run with --pin-csp");
  assert.ok(csp.startsWith("default-src 'none'"));
  assert.ok(!/https?:|\*|unsafe/.test(csp), "no hosts, wildcards or unsafe sources");
  assert.ok(!/<script[^>]+src=|<link[^>]+href="https?:/.test(page), "no external scripts or styles");
});

await check("the script never writes HTML", () => {
  for (const banned of ["innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval(", "new Function"]) {
    assert.ok(!script.includes(banned), `uses ${banned}`);
  }
});

await check("the stylesheet loads nothing from other hosts", () => {
  const css = readFileSync(join(here, "..", "balance.css"), "utf8");
  assert.ok(!/url\(\s*["']?(https?:|\/\/)/.test(css));
  assert.ok(!/@import/.test(css));
});

// MARK: Decoding

const sandbox = { atob, Blob, DecompressionStream, TextDecoder, URL, console };
vm.createContext(sandbox);
vm.runInContext(script, sandbox);
const page$ = sandbox.SpltBalanceLink;
page$.setLocale("en-GB");

const fragmentOf = (file) => readFileSync(join(here, file), "utf8").trim().split("#")[1];
const smallLink = readFileSync(join(here, "fixture.txt"), "utf8").trim();
const largeLink = readFileSync(join(here, "fixture-large.txt"), "utf8").trim();

await check("decodes the app's fixture", async () => {
  assert.ok(smallLink.startsWith("https://harrypakhale98.github.io/Splt/b/#"));
  const snapshot = await page$.decodeFragment(fragmentOf("fixture.txt"));
  assert.equal(snapshot.name, "Lisbon trip <b>");
  assert.deepEqual(Array.from(snapshot.members, (m) => m.name), ["Maya", "Leo", "Priya", "Zoë Ångström"]);
  assert.deepEqual(Array.from(snapshot.members, (m) => m.hue), [0, 5, 10, 2]);
  assert.equal(snapshot.members[3].left, true);
  assert.equal(snapshot.sharedBy, 0);
  assert.equal(snapshot.createdAt.toISOString(), "2026-11-10T18:40:00.000Z");
  assert.match(page$.subtitle(snapshot), /^7\s?–\s?14 Nov · 3 people$/u);
  assert.equal(snapshot.expenses.length, 2);
  assert.equal(snapshot.expenses[1].title, "<img src=x onerror=alert(1)>");
});

await check("Leo pays Maya €84.20", async () => {
  const snapshot = await page$.decodeFragment(fragmentOf("fixture.txt"));
  const leo = page$.describePerson(snapshot, 1);
  assert.equal(leo.pays.length, 1);
  assert.equal(snapshot.members[leo.pays[0].to].name, "Maya");
  assert.equal(page$.money(snapshot, leo.paysTotal[0].amount, leo.paysTotal[0].currency), "€84.20");
  const dinner = page$.expenseFor(snapshot.expenses[0], 1);
  assert.equal(dinner.net, -2400);
  const maya = page$.describePerson(snapshot, 0);
  assert.equal(maya.pays.length, 0);
  assert.equal(maya.gets.length, 2);
  const priya = page$.describePerson(snapshot, 2);
  assert.deepEqual(
    Array.from(priya.paysTotal, (part) => page$.money(snapshot, part.amount, part.currency)),
    ["€15.00", "JP¥1,200"]
  );
});

await check("decodes a large group", async () => {
  const snapshot = await page$.decodeFragment(fragmentOf("fixture-large.txt"));
  assert.equal(snapshot.members.length, 30);
  assert.equal(snapshot.expenses.length, 10);
  assert.equal(snapshot.expenses[0].shares.length, 30);
});

// MARK: Links that don't open

const pack = (value) => deflateRawSync(Buffer.from(typeof value === "string" ? value : JSON.stringify(value)))
  .toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const valid = { v: 1, n: "Flat", c: [["EUR", 2]], m: [["A", 0, 0], ["B", 1, 0]], x: [[0, 1, 500, 0]], s: 0, t: 1794336000 };

async function problem(fragment) {
  try {
    await page$.decodeFragment(fragment);
  } catch (error) {
    assert.equal(error.constructor.name, "LinkProblem", `threw ${error}`);
    return error.kind;
  }
  assert.fail("decoded a bad link");
}

await check("accepts a minimal hand-made link", async () => {
  const snapshot = await page$.decodeFragment(pack(valid));
  assert.equal(snapshot.expenses, null);
});

const joinID = "0E1F2A3B-4C5D-4E6F-8A9B-0C1D2E3F4A5B";
const joined = { ...valid, j: ["https://www.icloud.com/share/0AbCdEfGh", 1, joinID] };

await check("reads an invite made for one member", async () => {
  const snapshot = await page$.decodeFragment(pack(joined));
  assert.equal(snapshot.join.person, 1);
  assert.equal(snapshot.join.id, joinID);
  assert.equal(page$.joinLink(snapshot.join, "B"),
    "splt://join?share=" + encodeURIComponent("https://www.icloud.com/share/0AbCdEfGh") + "&as=" + joinID + "&name=B");
  assert.equal((await page$.decodeFragment(pack(valid))).join, null);
});

await check("refuses invites that aren't iCloud's", async () => {
  const cases = {
    "another host": ["https://evil.example/share/x", 1, joinID],
    "lookalike host": ["https://icloud.com.evil.example/x", 1, joinID],
    "plain http": ["http://www.icloud.com/share/x", 1, joinID],
    "script url": ["javascript:alert(1)", 1, joinID],
    "nobody": ["https://www.icloud.com/share/x", 9, joinID],
    "bad id": ["https://www.icloud.com/share/x", 1, "not-an-id"],
    "short": ["https://www.icloud.com/share/x", 1]
  };
  for (const [name, j] of Object.entries(cases)) {
    const kind = await problem(pack({ ...valid, j }));
    assert.ok(kind === "broken", `${name}: ${kind}`);
  }
});

await check("reads one invite for the whole group chat", async () => {
  const group = { ...valid, k: ["https://www.icloud.com/share/0AbCdEfGh", [[1, joinID]]] };
  const snapshot = await page$.decodeFragment(pack(group));
  assert.equal(snapshot.join, null);
  assert.equal(snapshot.groupJoin.seats.length, 1);
  assert.equal(snapshot.groupJoin.seats[0].person, 1);
  assert.equal(page$.joinLink({ url: snapshot.groupJoin.url, id: null }, "B"),
    "splt://join?share=" + encodeURIComponent("https://www.icloud.com/share/0AbCdEfGh"));
  assert.equal(page$.joinLink({ url: snapshot.groupJoin.url, id: joinID }, "Hana Sato"),
    "splt://join?share=" + encodeURIComponent("https://www.icloud.com/share/0AbCdEfGh") + "&as=" + joinID + "&name=Hana%20Sato");
  const cases = {
    "nobody waiting": ["https://www.icloud.com/share/x", []],
    "seat for nobody": ["https://www.icloud.com/share/x", [[9, joinID]]],
    "seat without id": ["https://www.icloud.com/share/x", [[1]]],
    "another host": ["https://evil.example/x", [[1, joinID]]]
  };
  for (const [name, k] of Object.entries(cases)) {
    const kind = await problem(pack({ ...valid, k }));
    assert.ok(kind === "broken", `${name}: ${kind}`);
  }
});

await check("initials match the app", () => {
  assert.equal(page$.initial("Hana Sato"), "HS");
  assert.equal(page$.initial("Priya"), "P");
  assert.equal(page$.initial("  maya   de la Cruz "), "MC");
});

await check("refuses broken and hostile links calmly", async () => {
  const smallFragment = fragmentOf("fixture.txt");
  const cases = {
    "not base64": "abc$%",
    "cut short": smallFragment.slice(0, smallFragment.length / 2),
    "not deflate": "AAAAAAAAAAAA",
    "not JSON": pack("hello"),
    "a list": pack([1, 2]),
    "no version": pack({ ...valid, v: undefined }),
    "member as object": pack({ ...valid, m: [{ name: "A" }] }),
    "hue out of range": pack({ ...valid, m: [["A", 12, 0], ["B", 1, 0]] }),
    "transfer to nobody": pack({ ...valid, x: [[0, 5, 500, 0]] }),
    "paying yourself": pack({ ...valid, x: [[0, 0, 500, 0]] }),
    "negative transfer": pack({ ...valid, x: [[0, 1, -5, 0]] }),
    "fractional amount": pack({ ...valid, x: [[0, 1, 5.5, 0]] }),
    "bad currency": pack({ ...valid, c: [["<script>", 2]] }),
    "sharer out of range": pack({ ...valid, s: 7 }),
    "empty name": pack({ ...valid, n: "   " }),
    "name as HTML object": pack({ ...valid, n: { toString: 1 } }),
    "bad day": pack({ ...valid, d: ["2026-02-30", "2026-03-01"] }),
    "expense share for nobody": pack({ ...valid, e: [["X", "2026-11-01", 0, 100, [[0, 100]], [[9, 100]]]] }),
    "huge payload": pack({ ...valid, n: "x".repeat(300000) })
  };
  for (const [name, fragment] of Object.entries(cases)) {
    const kind = await problem(fragment);
    assert.ok(kind === "broken", `${name}: ${kind}`);
  }
  assert.equal(await problem(pack({ ...valid, v: 2 })), "newer");
});

console.log(`\nfixture link: ${smallLink.length} characters`);
console.log(`30 people, 10 expenses split among all: ${largeLink.length} characters`);
if (failures) {
  console.log(`\n${failures} failed`);
  process.exit(1);
}
console.log("\nall passed");
