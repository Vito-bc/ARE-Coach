"use strict";

// PROOF BY CONSTRUCTION for the read-only export guard.
//
// Three review cycles found three escapes, all one class: an unwrapped
// Firestore object reachable from a wrapped one (.ref, then .parent/
// .firestore/.query, then docChanges()). Every test in
// read_only_escape.spec.cjs and test/read_only_db.test.js asserts on a
// SPECIFIC named path, so that method can only ever be as complete as the
// last person's imagination -- the next reviewer finds the next property
// nobody enumerated.
//
// This spec closes the CLASS instead. It breadth-first walks the object
// graph reachable from makeReadOnlyFirestore(db) using the REAL SDK against
// the emulator (mocks would only prove things about the mocks), enumerating
// own AND prototype property names at every node rather than a list of
// properties someone thought of, and asserts one invariant:
//
//   every object reachable from the wrapped db that exposes any of
//   set/update/delete/create/add/recursiveDelete/batch/bulkWriter/
//   runTransaction must throw the guard error when that method is called.
//
// A new SDK version growing a new back-pointer, or a new builder method
// returning an unwrapped Query, fails this test without anyone editing it.
// Failures print the exact property path that reached the object, so the
// hole is diagnosable from one read of the CI log.
//
// SCOPE, stated rather than silently assumed: `_`-prefixed properties are
// skipped. `ref._firestore` is the raw client on every reference, and no
// Proxy can hide it -- this guard is a defence against a contributor
// reaching for a plausible PUBLIC API by accident (the actual failure mode
// all three escapes had), not a sandbox against deliberate private-field
// access, which is unachievable in-process anyway (nothing stops code from
// calling getFirestore() itself). Everything reachable through the public
// surface is in scope and is walked.
//
// Run (mirrors this repo's other emulator-backed specs):
//   npx --yes firebase-tools@15.8.0 emulators:exec --only firestore \
//     --project demo-are-coach --config firebase.test.json \
//     "node --test tools/backup_restore/integration/read_only_reachability.spec.cjs"

const { test, before, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { makeReadOnlyFirestore } = require("../src/read_only_db");

const PROJECT_ID = "demo-are-coach";
const EMULATOR_HOST = "127.0.0.1:8087";
const ROOT = "reach_walk";

const GUARD_ERROR = /Read-only Firestore guard/;

// Walk bounds. Deliberately generous: if a bound is hit the test FAILS
// rather than quietly reporting a pass on a truncated walk.
const MAX_DEPTH = 6;
const MAX_NODES = 20000;
const MAX_EXPANSIONS = 600;
const MAX_ARRAY_ELEMENTS = 3;

// The invariant's subject: every mutating entry point the SDK exposes on a
// Firestore, a DocumentReference or a CollectionReference.
//
// Every argument here is DELIBERATELY INVALID, which makes the whole walk
// non-destructive while classifying exactly as well:
//   - a guarded object throws the guard error, because the guard replaces
//     the method outright and nothing ever reaches argument validation;
//   - a raw object throws the SDK's own validation error (verified against
//     the real SDK: add/set/create/update/delete/recursiveDelete/
//     runTransaction all throw synchronously on these args and write
//     nothing), or, for batch()/bulkWriter(), returns a stager that commits
//     nothing.
// So "threw the guard error" still means guarded and anything else still
// means raw -- but the walk cannot write. That matters: from a raw root
// Firestore, listCollections() reaches EVERY collection in the database, so
// a walk that probed with valid data wrote junk into whatever else lives in
// the emulator (it corrupted drill.spec.cjs's collections mid-run when
// these specs were first run together). A test that probes the whole
// database for write-ability must not be the thing that writes to it.
const MUTATING_METHODS = {
  set: () => [undefined],
  update: () => [undefined],
  create: () => [undefined],
  add: () => [undefined],
  delete: () => [{ lastUpdateTime: "not-a-timestamp" }],
  recursiveDelete: () => [null],
  batch: () => [],
  bulkWriter: () => [],
  runTransaction: () => [null],
};

// Navigation: how the walk moves between objects. Every entry is public SDK
// API. Note this list only affects REACH (how many objects get inspected),
// never the invariant above -- so a missing entry here can only make the
// test weaker in coverage, never wrong, and property enumeration below
// still discovers back-pointers nobody listed.
const NAVIGATION_CALLS = {
  doc: () => ["d1"],
  collection: () => ["sub"],
  collectionGroup: () => ["sub"],
  withConverter: () => [null],
  get: () => [],
  listDocuments: () => [],
  listCollections: () => [],
  where: () => ["n", "==", 1],
  orderBy: () => ["n"],
  limit: () => [1],
  limitToLast: () => [1],
  offset: () => [0],
  select: () => ["n"],
  startAt: () => [0],
  startAfter: () => [0],
  endAt: () => [999],
  endBefore: () => [999],
  count: () => [],
  aggregate: () => [{ total: { count: {} } }],
  docChanges: () => [],
  explain: () => [],
};

// `onSnapshot` and `explainStream` are the public read routes the walk does
// NOT open: both start a live stream with its own network lifecycle, and
// racing their callbacks inside a breadth-first walk would buy flakiness in
// CI for routes this tool structurally never uses. `onSnapshot` is guarded
// by construction in src/read_only_db.js and covered by a deterministic
// named test in read_only_escape.spec.cjs instead. Stated here rather than
// silently skipped, so the next auditor knows exactly where the walk stops.

const SKIP_PROPS = new Set([
  "constructor", "prototype", "caller", "callee", "arguments", "__proto__", "length", "name",
]);

let rawDb;

before(() => {
  if (process.env.FIRESTORE_EMULATOR_HOST !== EMULATOR_HOST) {
    throw new Error(`Local emulator required (FIRESTORE_EMULATOR_HOST must be ${EMULATOR_HOST})`);
  }
  const app = initializeApp({ projectId: PROJECT_ID }, "read-only-reachability-spec");
  rawDb = getFirestore(app);
});

beforeEach(async () => {
  await rawDb.recursiveDelete(rawDb.collection(ROOT));
});

/**
 * Enough data that queries and snapshots are NON-EMPTY -- an empty
 * QuerySnapshot has no .docs to walk and would prove nothing -- and that a
 * document has a subcollection, so listCollections()/.parent have something
 * real to return.
 */
async function seed() {
  for (const id of ["d1", "d2"]) {
    await rawDb.collection(ROOT).doc(id).set({ n: 1, label: id });
    await rawDb.collection(ROOT).doc(id).collection("sub").doc("s1").set({ n: 1 });
  }
}

/**
 * Exact contents of the walk's own collection, read through the RAW client.
 * Compared before and after each walk so "the walk writes nothing" is a
 * tested property rather than a claim about the arguments above. Scoped to
 * the sandbox rather than the whole database because these specs share one
 * emulator with drill.spec.cjs, which is mutating its own collections
 * concurrently -- a database-wide fingerprint would be flaky for reasons
 * that have nothing to do with this guard.
 */
async function sandboxFingerprint() {
  const out = {};
  const docs = await rawDb.collection(ROOT).listDocuments();
  for (const docRef of docs.sort((a, b) => (a.id < b.id ? -1 : 1))) {
    const snap = await docRef.get();
    out[docRef.id] = snap.exists ? JSON.stringify(snap.data()) : "<missing>";
    for (const sub of await docRef.listCollections()) {
      const subSnap = await sub.get();
      out[`${docRef.id}/${sub.id}`] = subSnap.docs
        .map((d) => `${d.id}=${JSON.stringify(d.data())}`)
        .join("|");
    }
  }
  return out;
}

/** Real class name, read past the Proxy (proxy.constructor comes back bound). */
function typeName(obj) {
  try {
    const proto = Object.getPrototypeOf(obj);
    return (proto && proto.constructor && proto.constructor.name) || typeof obj;
  } catch {
    return "unknown";
  }
}

function safeRead(obj, prop) {
  try {
    return obj[prop];
  } catch {
    return undefined;
  }
}

/** Own + inherited property names, minus internals (see SCOPE above). */
function propertyNames(obj) {
  const names = new Set();
  let cur = obj;
  let hops = 0;
  while (cur && cur !== Object.prototype && hops < 10) {
    try {
      for (const n of Object.getOwnPropertyNames(cur)) names.add(n);
    } catch {
      break;
    }
    cur = Object.getPrototypeOf(cur);
    hops += 1;
  }
  return [...names].filter((n) => !SKIP_PROPS.has(n) && !n.startsWith("_") && !n.startsWith("$"));
}

/**
 * De-dup key for EXPANSION only. Keyed by SHAPE -- the object's SDK type
 * plus the kind of step that produced it -- not by document path. Whether
 * an object is guarded depends on the ROUTE that built it, never on which
 * document it points at, so `reach_walk/d1` and `reach_walk/d2` are the
 * same question asked twice. Keying by path instead made the walk descend
 * forever into synthetic doc/subcollection chains (.doc("d1") ->
 * .collection("sub") -> .doc("d1") -> ...), each a fresh key, each costing
 * a round of network calls.
 *
 * Every discovered object is still TESTED before this de-dup applies -- so
 * collapsing a raw object onto an already-expanded guarded one can only
 * hide deeper reach, never the escape itself.
 */
function visitKey(obj, step) {
  return `${typeName(obj)}|${step}`;
}

function isWalkable(value) {
  return value !== null && typeof value === "object";
}

/**
 * Calls one mutating method and classifies the outcome. The guard throws
 * SYNCHRONOUSLY, so anything else -- a different error, or no error at all
 * (a returned promise means the write is already in flight) -- is an
 * object that escaped the guard.
 */
function classifyMutation(obj, name, args) {
  try {
    const result = obj[name](...args);
    if (result && typeof result.then === "function") result.then(() => {}, () => {});
    return { guarded: false, why: "call returned without throwing -- this object is not guarded" };
  } catch (err) {
    if (GUARD_ERROR.test(err && err.message)) return { guarded: true };
    return { guarded: false, why: `threw a non-guard error: ${err && err.message}` };
  }
}

/** Every object one hop out from `node`, labelled with the step that got there. */
async function edgesFrom(node) {
  const edges = [];
  const obj = node.value;

  const push = (value, step) => {
    if (!isWalkable(value)) return;
    if (Array.isArray(value)) {
      value.slice(0, MAX_ARRAY_ELEMENTS).forEach((el, i) => {
        if (isWalkable(el)) edges.push({ value: el, step: `${step}[${i}]` });
      });
      return;
    }
    edges.push({ value, step });
  };

  // 1. Property reads -- the generic half. Nothing here is named in
  //    advance, so a back-pointer added by a future SDK version is
  //    discovered without this file changing.
  for (const name of propertyNames(obj)) {
    if (name in MUTATING_METHODS) continue; // called by the invariant, not followed
    const value = safeRead(obj, name);
    if (typeof value === "function") continue; // reached via NAVIGATION_CALLS
    push(value, `.${name}`);
  }

  // 2. Navigation calls.
  for (const [name, argsFor] of Object.entries(NAVIGATION_CALLS)) {
    const fn = safeRead(obj, name);
    if (typeof fn !== "function") continue;
    const args = argsFor();
    let result;
    try {
      result = obj[name](...args);
      if (result && typeof result.then === "function") result = await result;
    } catch {
      continue; // e.g. startAt() without orderBy() -- not a reachable route from here
    }
    push(result, `.${name}(${args.map((a) => JSON.stringify(a)).join(", ")})`);
  }

  // 3. Callback- and stream-shaped traversals, which hand objects to the
  //    caller instead of returning them.
  const forEach = safeRead(obj, "forEach");
  if (typeof forEach === "function" && typeName(obj).includes("QuerySnapshot")) {
    const seen = [];
    try {
      obj.forEach((d) => seen.push(d));
    } catch { /* not a snapshot-shaped forEach */ }
    seen.slice(0, MAX_ARRAY_ELEMENTS).forEach((d, i) => push(d, `.forEach()[${i}]`));
  }

  const stream = safeRead(obj, "stream");
  if (typeof stream === "function") {
    try {
      const emitted = [];
      for await (const doc of obj.stream()) {
        emitted.push(doc);
        if (emitted.length >= MAX_ARRAY_ELEMENTS) break;
      }
      emitted.forEach((d, i) => push(d, `.stream()[${i}]`));
    } catch { /* not stream-shaped */ }
  }

  // 4. getAll() needs references as arguments; give it one reached from
  //    this same node so the result belongs to this path.
  const getAll = safeRead(obj, "getAll");
  if (typeof getAll === "function") {
    try {
      const ref = obj.collection(ROOT).doc("d1");
      const snaps = await obj.getAll(ref);
      push(snaps, `.getAll(<${ROOT}/d1>)`);
    } catch { /* not a Firestore-shaped getAll */ }
  }

  return edges;
}

/**
 * Breadth-first walk. Returns every escape found, each with the exact
 * property path that reached it.
 */
async function walkForEscapes(root, rootLabel) {
  const escapes = [];
  const expanded = new Set();
  const typesSeen = new Set();
  const queue = [{ value: root, path: rootLabel, step: "<root>", depth: 0 }];
  let tested = 0;

  while (queue.length > 0) {
    const node = queue.shift();
    tested += 1;
    if (tested > MAX_NODES) {
      throw new Error(`Walk exceeded MAX_NODES (${MAX_NODES}) -- tune the bounds, do not narrow the walk.`);
    }
    typesSeen.add(typeName(node.value));

    // THE INVARIANT.
    for (const [name, argsFor] of Object.entries(MUTATING_METHODS)) {
      if (typeof safeRead(node.value, name) !== "function") continue;
      const outcome = classifyMutation(node.value, name, argsFor());
      if (!outcome.guarded) {
        escapes.push({
          path: `${node.path} -> .${name}()`,
          type: typeName(node.value),
          why: outcome.why,
        });
      }
    }

    if (node.depth >= MAX_DEPTH) continue;
    const key = visitKey(node.value, node.step);
    if (expanded.has(key)) continue;
    expanded.add(key);
    if (expanded.size > MAX_EXPANSIONS) {
      throw new Error(`Walk exceeded MAX_EXPANSIONS (${MAX_EXPANSIONS}) -- tune the bounds, do not narrow the walk.`);
    }

    for (const edge of await edgesFrom(node)) {
      queue.push({
        value: edge.value,
        path: `${node.path} -> ${edge.step}`,
        step: edge.step,
        depth: node.depth + 1,
      });
    }
  }

  return { escapes, tested, expanded: expanded.size, typesSeen };
}

function formatEscapes(escapes) {
  return escapes
    .map((e, i) => `  ${i + 1}. [${e.type}] ${e.path}\n     ${e.why}`)
    .join("\n");
}

test("no unguarded Firestore object is reachable from the wrapped db", async () => {
  await seed();
  const before = await sandboxFingerprint();
  const db = makeReadOnlyFirestore(rawDb);

  const { escapes, tested, expanded, typesSeen } = await walkForEscapes(
    db,
    "makeReadOnlyFirestore(db)"
  );

  assert.deepStrictEqual(
    await sandboxFingerprint(),
    before,
    "the walk itself modified data -- its probes are supposed to be non-destructive"
  );

  // Sanity: a walk that reached nothing interesting could "pass" while
  // proving nothing, so require the real SDK types to have been inspected.
  for (const required of [
    "Firestore",
    "CollectionReference",
    "DocumentReference",
    "Query",
    "QuerySnapshot",
    "QueryDocumentSnapshot",
    "DocumentSnapshot",
  ]) {
    assert.ok(
      typesSeen.has(required),
      `walk never reached a ${required} -- it is not proving what it claims. Saw: ${[...typesSeen].sort().join(", ")}`
    );
  }
  assert.ok(tested > 50, `walk only inspected ${tested} objects -- too shallow to be meaningful`);

  assert.equal(
    escapes.length,
    0,
    `${escapes.length} reachable object(s) accepted a mutating call instead of throwing the read-only guard:\n${formatEscapes(escapes)}\n`
  );

  console.log(
    `REACHABILITY OK: ${tested} objects inspected, ${expanded} expanded, ` +
      `${typesSeen.size} SDK types (${[...typesSeen].sort().join(", ")}), 0 escapes.`
  );
});

test("the walk actually detects an escape -- negative control", async () => {
  await seed();

  // A guard with one hole punched in it: `.collection()` hands back the RAW
  // CollectionReference. Nothing else changes. This is the permanent proof
  // that the walk above can fail -- a guard test that cannot fail is
  // worthless, and asserting that in CI beats asserting it once by hand.
  const leaky = new Proxy(makeReadOnlyFirestore(rawDb), {
    get(target, prop, receiver) {
      if (prop === "collection") return (...args) => rawDb.collection(...args);
      return Reflect.get(target, prop, receiver);
    },
  });

  const before = await sandboxFingerprint();
  const { escapes } = await walkForEscapes(leaky, "leakyGuard(db)");

  // Even walking a deliberately unguarded client, nothing is written: this
  // walk reaches the raw root Firestore and therefore every collection in
  // the database, so non-destructiveness matters most in exactly this case.
  assert.deepStrictEqual(
    await sandboxFingerprint(),
    before,
    "walking an UNGUARDED client modified data -- the probes must stay non-destructive even then"
  );

  assert.ok(escapes.length > 0, "the walk failed to notice a deliberately unguarded collection()");
  const paths = escapes.map((e) => e.path);
  assert.ok(
    paths.some((p) => p.includes(".collection(")),
    `escape paths must name the route that reached the raw object. Got:\n${formatEscapes(escapes)}`
  );
  // And the report must be specific enough to fix from: it names the
  // mutating method, not just "something is wrong".
  assert.ok(
    paths.some((p) => /-> \.(add|set|update|delete|create|batch|bulkWriter|runTransaction|recursiveDelete)\(\)$/.test(p)),
    `escape paths must name the mutating call. Got:\n${formatEscapes(escapes)}`
  );
});
