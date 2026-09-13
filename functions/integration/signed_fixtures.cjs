// Ephemeral TEST ONLY PKI. Never imported by production code or deployed.
const { execFileSync } = require("node:child_process");
const { mkdtempSync, readFileSync, writeFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { X509Certificate, sign } = require("node:crypto");
function fixtures() {
  const dir = mkdtempSync(join(tmpdir(), "are-apple-test-pki-"));
  const openssl = process.env.OPENSSL || "openssl";
  writeFileSync(join(dir, "openssl.cnf"), "[req]\ndistinguished_name=dn\n[dn]\n");
  const run = (...args) => execFileSync(openssl, args, { cwd: dir, stdio: "pipe", env: { ...process.env, OPENSSL_CONF: join(dir, "openssl.cnf") } });
  const key = name => run("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${name}.key`);
  key("root");
  run("req", "-new", "-x509", "-key", "root.key", "-out", "root.pem", "-days", "30", "-subj", "/CN=ARE TEST ONLY Root", "-addext", "basicConstraints=critical,CA:TRUE");
  for (const [name, issuer, extension] of [["intermediate", "root", "basicConstraints=critical,CA:TRUE\n1.2.840.113635.100.6.2.1=DER:05:00"],
    ["leaf", "intermediate", "basicConstraints=critical,CA:FALSE\n1.2.840.113635.100.6.11.1=DER:05:00"]]) {
    key(name);
    run("req", "-new", "-key", `${name}.key`, "-out", `${name}.csr`, "-subj", `/CN=ARE TEST ONLY ${name}`);
    writeFileSync(join(dir, `${name}.ext`), extension);
    run("x509", "-req", "-in", `${name}.csr`, "-CA", `${issuer}.pem`, "-CAkey", `${issuer}.key`, "-CAcreateserial", "-out", `${name}.pem`, "-days", "20", "-extfile", `${name}.ext`);
  }
  const chain = ["leaf", "intermediate", "root"].map(name => new X509Certificate(readFileSync(join(dir, `${name}.pem`))).raw.toString("base64"));
  const privateKey = readFileSync(join(dir, "leaf.key"));
  return { root: readFileSync(join(dir, "root.pem")),
    signed(payload) {
      const data = [JSON.stringify({ alg: "ES256", x5c: chain }), JSON.stringify(payload)].map(v => Buffer.from(v).toString("base64url")).join(".");
      return `${data}.${sign("sha256", Buffer.from(data), { key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
    },
    close: () => rmSync(dir, { recursive: true }),
  };
}
module.exports = { fixtures };
