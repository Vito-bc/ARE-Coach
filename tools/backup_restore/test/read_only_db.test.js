"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { makeReadOnlyFirestore } = require("../src/read_only_db");

// A minimal fake that shapes itself like the pieces of the Admin SDK's
// Firestore/CollectionReference/DocumentReference this tool actually calls,
// so this test needs no real Firestore instance or emulator.
function fakeDb() {
  const fakeDocRef = {
    id: "d1",
    set: () => "wrote",
    update: () => "wrote",
    delete: () => "wrote",
    create: () => "wrote",
    get: () => "read",
    collection: (id) => fakeCollectionRef(id),
  };
  function fakeCollectionRef(id) {
    return {
      id,
      add: () => "wrote",
      listDocuments: () => "read",
      doc: (docId) => ({ ...fakeDocRef, id: docId }),
    };
  }
  return {
    batch: () => "wrote",
    bulkWriter: () => "wrote",
    runTransaction: () => "wrote",
    listCollections: () => "read",
    collection: (id) => fakeCollectionRef(id),
    doc: (path) => ({ ...fakeDocRef, id: path }),
  };
}

test("blocks db.batch/bulkWriter/runTransaction", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  assert.throws(() => db.batch(), /Read-only Firestore guard/);
  assert.throws(() => db.bulkWriter(), /Read-only Firestore guard/);
  assert.throws(() => db.runTransaction(), /Read-only Firestore guard/);
});

test("allows read methods straight through", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  assert.equal(db.listCollections(), "read");
});

test("blocks set/update/delete/create on a document reached via db.collection().doc()", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const doc = db.collection("users").doc("u1");
  assert.throws(() => doc.set({}), /Read-only Firestore guard/);
  assert.throws(() => doc.update({}), /Read-only Firestore guard/);
  assert.throws(() => doc.delete(), /Read-only Firestore guard/);
  assert.throws(() => doc.create({}), /Read-only Firestore guard/);
  assert.equal(doc.get(), "read");
});

test("blocks add() on a collection reference reached via db.doc().collection()", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const nested = db.doc("users/u1").collection("attempts");
  assert.throws(() => nested.add({}), /Read-only Firestore guard/);
});

test("blocks writes arbitrarily deep, not just one level of nesting", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  const deep = db.collection("a").doc("b").collection("c").doc("d");
  assert.throws(() => deep.set({}), /Read-only Firestore guard/);
});

test("blocked methods still identify themselves in the error", () => {
  const db = makeReadOnlyFirestore(fakeDb());
  assert.throws(() => db.collection("x").doc("y").update({}), /"update"/);
});
