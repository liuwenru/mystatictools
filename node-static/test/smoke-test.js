'use strict';
// 用法: node smoke-test.js <期望版本，如 v26.13.0，空则读 NODE_EXPECTED_VERSION> <fixtures 目录>
// 不调用 shell 和外部命令，可在空根文件系统（scratch）中运行；只连接 127.0.0.1。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const expected = process.argv[2] || process.env.NODE_EXPECTED_VERSION;
const fixtures = process.argv[3];
if (!expected || !fixtures) {
  console.error('用法: node smoke-test.js <期望版本> <fixtures 目录>');
  process.exit(2);
}
const nodeRoot = path.resolve(path.dirname(process.execPath), '..');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'node-static-test-'));
let failed = 0;

async function check(name, fn, { optional = false } = {}) {
  try {
    const detail = await fn();
    console.log(`PASS ${name}${detail ? `: ${detail}` : ''}`);
  } catch (err) {
    if (optional) {
      console.log(`INFO ${name}: ${err.message}`);
    } else {
      failed++;
      console.log(`FAIL ${name}: ${err.stack || err}`);
    }
  }
}

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

(async () => {
  await check('版本', () => {
    assert.equal(process.version, expected);
    return `${process.version} ${process.arch} openssl=${process.versions.openssl} icu=${process.versions.icu}`;
  });

  await check('Intl full-icu 与内置时区数据', () => {
    const month = new Intl.DateTimeFormat('zh-CN', { month: 'long', timeZone: 'UTC' }).format(Date.UTC(2020, 0, 1));
    assert.equal(month, '一月');
    const shanghai = new Date(0).toLocaleString('en-US', { timeZone: 'Asia/Shanghai', hour12: false });
    assert.match(shanghai, /08:00:00/);
    return `${month}; ${shanghai}`;
  });

  await check('Temporal', () => {
    assert.equal(typeof Temporal, 'object');
    const next = Temporal.PlainDate.from('2026-11-03').add({ days: 30 }).toString();
    assert.equal(next, '2026-12-03');
    return next;
  });

  await check('crypto（OpenSSL）', async () => {
    const crypto = require('node:crypto');
    assert.equal(crypto.createHash('sha256').update('abc').digest('hex'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    assert.ok(crypto.getHashes().includes('sha3-256'));
    const key = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    const enc = crypto.createCipheriv('aes-256-gcm', key, iv);
    const data = Buffer.concat([enc.update('offline'), enc.final()]);
    const dec = crypto.createDecipheriv('aes-256-gcm', key, iv);
    dec.setAuthTag(enc.getAuthTag());
    assert.equal(Buffer.concat([dec.update(data), dec.final()]).toString(), 'offline');
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
    const sig = crypto.sign(null, Buffer.from('x'), privateKey);
    assert.ok(crypto.verify(null, Buffer.from('x'), publicKey, sig));
    const digest = await crypto.webcrypto.subtle.digest('SHA-256', Buffer.from('abc'));
    assert.equal(Buffer.from(digest).toString('hex').slice(0, 8), 'ba7816bf');
    return `${crypto.getCiphers().length} ciphers`;
  });

  await check('zlib gzip/brotli/zstd', () => {
    const zlib = require('node:zlib');
    const input = Buffer.from('static node '.repeat(1000));
    assert.deepEqual(zlib.gunzipSync(zlib.gzipSync(input)), input);
    assert.deepEqual(zlib.brotliDecompressSync(zlib.brotliCompressSync(input)), input);
    assert.deepEqual(zlib.zstdDecompressSync(zlib.zstdCompressSync(input)), input);
  });

  await check('node:sqlite', () => {
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(':memory:');
    db.exec('create table t(v text); insert into t values (\'ok\')');
    assert.equal(db.prepare('select v from t').get().v, 'ok');
    db.close();
  });

  await check('文件读写', () => {
    const file = path.join(work, 'a.txt');
    fs.writeFileSync(file, '中文 ok\n');
    assert.equal(fs.readFileSync(file, 'utf8'), '中文 ok\n');
    fs.renameSync(file, `${file}.bak`);
    assert.deepEqual(fs.readdirSync(work), ['a.txt.bak']);
  });

  await check('子进程（直接 exec node 自身）', () => {
    const out = execFileSync(process.execPath, ['-e', 'process.stdout.write(String(6*7))']);
    assert.equal(out.toString(), '42');
  });

  await check('worker_threads', () => new Promise((resolve, reject) => {
    const { Worker } = require('node:worker_threads');
    const w = new Worker('require("node:worker_threads").parentPort.postMessage(21*2)', { eval: true });
    w.once('message', (v) => { try { assert.equal(v, 42); resolve(); } catch (e) { reject(e); } });
    w.once('error', reject);
  }));

  await check('HTTP 服务与 fetch（127.0.0.1）', async () => {
    const http = require('node:http');
    const server = http.createServer((req, res) => res.end(`hi ${req.url}`));
    const port = await listen(server);
    try {
      const res = await fetch(`http://127.0.0.1:${port}/x`);
      assert.equal(await res.text(), 'hi /x');
    } finally {
      server.close();
    }
  });

  await check('HTTPS/TLS（自签证书，127.0.0.1）', async () => {
    const https = require('node:https');
    const key = fs.readFileSync(path.join(fixtures, 'key.pem'));
    const cert = fs.readFileSync(path.join(fixtures, 'cert.pem'));
    const server = https.createServer({ key, cert }, (req, res) => res.end('tls ok'));
    const port = await listen(server);
    try {
      const body = await new Promise((resolve, reject) => {
        https.get({ host: '127.0.0.1', port, path: '/', ca: cert }, (res) => {
          let s = '';
          res.on('data', (d) => { s += d; });
          res.on('end', () => resolve(s));
        }).on('error', reject);
      });
      assert.equal(body, 'tls ok');
    } finally {
      server.close();
    }
  });

  await check('npm 离线打包并安装本地包', () => {
    const npmCli = path.join(nodeRoot, 'lib/node_modules/npm/bin/npm-cli.js');
    const env = {
      ...process.env,
      npm_config_cache: path.join(work, 'npm-cache'),
      npm_config_update_notifier: 'false',
      npm_config_fund: 'false',
      npm_config_audit: 'false',
      npm_config_offline: 'true',
    };
    const npm = (args, cwd) => execFileSync(process.execPath, [npmCli, ...args], { cwd, env }).toString().trim();
    const version = npm(['--version'], work);
    const project = path.join(work, 'project');
    fs.mkdirSync(project);
    fs.writeFileSync(path.join(project, 'package.json'), '{"name":"p","version":"1.0.0","private":true}\n');
    const tgz = npm(['pack', path.join(fixtures, 'local-pkg'), '--pack-destination', work], work).split('\n').pop();
    npm(['install', path.join(work, tgz)], project);
    const installed = path.join(project, 'node_modules/offline-local-pkg');
    assert.ok(!fs.lstatSync(installed).isSymbolicLink());
    const out = execFileSync(process.execPath, [path.join(installed, 'index.js')]).toString().trim();
    assert.equal(out, 'offline-local-pkg ok');
    return `npm ${version}`;
  });

  await check('原生扩展 .node 不能加载（预期失败）', () => {
    let error;
    try {
      require(path.join(fixtures, 'addon/hello.node'));
    } catch (err) {
      error = err;
    }
    assert.ok(error, '静态 node 意外加载成功了原生扩展');
    return error.message.split('\n')[0];
  });

  await check('DNS 解析 localhost（依赖 /etc/hosts，仅记录）', async () => {
    const r = await require('node:dns').promises.lookup('localhost');
    return `${r.address}`;
  }, { optional: true });

  fs.rmSync(work, { recursive: true, force: true });
  console.log(failed ? `\n${failed} 项失败` : '\n全部通过');
  process.exit(failed ? 1 : 0);
})();
