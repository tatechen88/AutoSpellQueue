#!/usr/bin/env node
/**
 * AutoSpellQueue -- syntax gate.
 *
 *   1. parses every .lua file in the repository with luaparse (luaVersion 5.1,
 *      i.e. the dialect the game client actually uses) and reports
 *      file:line:column plus the offending source line;
 *   2. lints the same files for constructs that are silently wrong on the
 *      *other* Lua version (the test runner is Lua 5.3 / fengari, the client is
 *      Lua 5.1). See docs/ARCHITECTURE.md section 6.
 *
 * Exit code 0 = clean, 1 = at least one error. Usage:
 *
 *   node tools/check-syntax.mjs
 *   node tools/check-syntax.mjs --quiet
 */
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const QUIET = process.argv.includes("--quiet");
const TOOLS_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(TOOLS_DIR, "..");
const SKIP_DIRS = new Set(["node_modules", ".git", "dist", ".scratch"]);

/* ------------------------------------------------------------------ files -- */

function collectLuaFiles(dir, found = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return found;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      collectLuaFiles(full, found);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".lua")) {
      found.push(full);
    }
  }
  return found;
}

const rel = (p) => path.relative(ROOT, p).split(path.sep).join("/");

/* ------------------------------------------------- Lua source sanitisation -- */
/* Replace comments and string literals with blanks (newlines preserved) so the
 * dual-version lint cannot fire on prose or on data inside a string.          */

function readLongBracket(src, i) {
  // src[i] === "["
  let j = i + 1;
  let eq = 0;
  while (src[j] === "=") {
    eq += 1;
    j += 1;
  }
  if (src[j] !== "[") return null;
  const close = "]" + "=".repeat(eq) + "]";
  const end = src.indexOf(close, j + 1);
  if (end === -1) return { end: src.length };
  return { end: end + close.length };
}

function stripLua(src) {
  const out = src.split("");
  const blank = (from, to) => {
    for (let k = from; k < to && k < out.length; k += 1) {
      if (out[k] !== "\n" && out[k] !== "\r") out[k] = " ";
    }
  };
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === "-" && src[i + 1] === "-") {
      const j = i + 2;
      const lb = src[j] === "[" ? readLongBracket(src, j) : null;
      if (lb) {
        blank(i, lb.end);
        i = lb.end;
      } else {
        let e = src.indexOf("\n", j);
        if (e === -1) e = src.length;
        blank(i, e);
        i = e;
      }
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < src.length) {
        if (src[j] === "\\") {
          j += 2;
          continue;
        }
        if (src[j] === c) {
          j += 1;
          break;
        }
        if (src[j] === "\n") break; // unterminated on this line; let the parser complain
        j += 1;
      }
      blank(i, j);
      i = j;
      continue;
    }
    if (c === "[") {
      const lb = readLongBracket(src, i);
      if (lb) {
        blank(i, lb.end);
        i = lb.end;
        continue;
      }
    }
    i += 1;
  }
  return out.join("");
}

function lineAt(code, index) {
  let line = 1;
  for (let i = 0; i < index && i < code.length; i += 1) {
    if (code[i] === "\n") line += 1;
  }
  return line;
}

/* ------------------------------------------------------------- dual compat -- */

const DUAL_COMPAT_RULES = [
  {
    // `local unpack = table.unpack or unpack` (the shim) is allowed; calling the
    // bare global is not, because Lua 5.3 removed it.
    pattern: /\bunpack\s*\(/g,
    message:
      "global unpack() 在 Lua 5.3（测试运行器）不存在；请加 shim：local unpack = table.unpack or unpack",
  },
  {
    pattern: /\bgoto\b/g,
    message: "goto 是 5.2+ 语法，Lua 5.1 客户端会直接报语法错误",
  },
  {
    pattern: /\/\//g,
    message:
      "`//` 在 Lua 5.1 里是行注释、在 5.3 里是整除；同一行代码在两端行为不同（静默错误）",
  },
  {
    pattern: /\b(?:setfenv|getfenv|loadstring|setn|foreach|foreachi)\s*\(/g,
    message: "该函数在 Lua 5.3 已移除，测试运行器会报 attempt to call a nil value",
  },
  {
    pattern: /\btable\.(?:getn|setn|foreach|foreachi)\s*\(/g,
    message: "table.getn/setn/foreach/foreachi 在 Lua 5.3 已移除",
  },
  {
    pattern: /\bmath\.(?:mod|log10|atan2)\s*\(/g,
    message: "math.mod/log10/atan2 在 Lua 5.3 已移除",
  },
  {
    pattern: /\bnewproxy\s*\(/g,
    message: "newproxy 在 Lua 5.3 已移除",
  },
];

/* ------------------------------------------------------------------ report -- */

function printParseError(displayPath, source, err) {
  const line = err.line ?? 0;
  const column = err.column ?? 0;
  let message = String(err.message ?? err);
  message = message.replace(/^\[\d+:\d+\]\s*/, "");
  const pad = String(line).length;
  console.log(`  FAIL  ${displayPath}`);
  console.log(`        ${displayPath}:${line}:${column}: ${message}`);
  const lines = source.split(/\r?\n/);
  if (line >= 1 && line <= lines.length) {
    console.log(`        ${" ".repeat(pad)} |`);
    console.log(`        ${line} | ${lines[line - 1]}`);
    console.log(`        ${" ".repeat(pad)} | ${" ".repeat(Math.max(0, column - 1))}^`);
  }
}

const files = collectLuaFiles(ROOT).sort();
let parseFailures = 0;
let lintFailures = 0;

console.log("AutoSpellQueue syntax check");
console.log(`  parser : luaparse, luaVersion=5.1 (客户端方言)`);
console.log(`  root   : ${ROOT}`);
console.log(`  files  : ${files.length} 个 .lua（跳过 ${[...SKIP_DIRS].join(", ")}）`);
console.log("");

if (files.length === 0) {
  console.log("  FAIL  没有找到任何 .lua 文件 —— 门禁配置有误");
  process.exit(1);
}

console.log("[1/2] 语法解析 (5.1)");
for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const display = rel(file);
  try {
    luaparse.parse(source, {
      luaVersion: "5.1",
      comments: false,
      scope: false,
      locations: true,
      ranges: false,
      wait: false,
      encodingMode: "none",
    });
    if (!QUIET) console.log(`  ok    ${display}`);
  } catch (err) {
    parseFailures += 1;
    printParseError(display, source, err);
  }
}

console.log("");
console.log("[2/2] 5.1/5.3 双兼容 lint");
for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const display = rel(file);
  const code = stripLua(source);
  const hits = [];
  for (const rule of DUAL_COMPAT_RULES) {
    rule.pattern.lastIndex = 0;
    let match;
    while ((match = rule.pattern.exec(code)) !== null) {
      hits.push({ index: match.index, token: match[0].trim(), message: rule.message });
    }
  }
  if (hits.length === 0) {
    if (!QUIET) console.log(`  ok    ${display}`);
    continue;
  }
  hits.sort((a, b) => a.index - b.index);
  for (const hit of hits) {
    lintFailures += 1;
    const line = lineAt(code, hit.index);
    const excerpt = (source.split(/\r?\n/)[line - 1] ?? "").trim();
    console.log(`  FAIL  ${display}:${line}: ${hit.message}`);
    console.log(`        代码: ${excerpt}`);
  }
}

console.log("");
if (parseFailures === 0 && lintFailures === 0) {
  console.log(`结果: ${files.length} 个文件全部通过（语法 0 错，双兼容 lint 0 错）`);
  process.exit(0);
}
console.log(`结果: 语法错误 ${parseFailures} 个文件，双兼容 lint 错误 ${lintFailures} 处`);
process.exit(1);
