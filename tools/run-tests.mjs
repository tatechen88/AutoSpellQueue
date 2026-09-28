#!/usr/bin/env node
/**
 * AutoSpellQueue -- unit test runner.
 *
 * Boots a fengari (Lua 5.3) state, fakes the game client (tests/wow_stub.lua),
 * loads the three *core* addon files with the varargs they expect
 * (`local ADDON_NAME, ns = ...`, all five core files share one ns table), then
 * executes tests/run.lua. AutoSpellQueue_Locale.lua and
 * AutoSpellQueue_Options.lua are deliberately not loaded: the core must work
 * without them (see docs/ARCHITECTURE.md, sections 2 and 6).
 *
 *   node tools/run-tests.mjs              # everything
 *   node tools/run-tests.mjs spec_cvar    # only specs whose name matches
 *
 * Exit code 0 = green, 1 = failure (or a Lua error while loading).
 */
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";

const TOOLS_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(TOOLS_DIR, "..");
const ADDON_NAME = "AutoSpellQueue";

/** Load order matters: Formula and CVar define ns.* before Core reads them. */
const CORE_FILES = [
  "AutoSpellQueue_Formula.lua",
  "AutoSpellQueue_Latency.lua",
  "AutoSpellQueue_CVar.lua",
  "AutoSpellQueue.lua",
];

/**
 * The rest of the client load order (see the .toc). Locale and Options are
 * loaded too, so the UI spec runs against the same namespace the game builds.
 * The *core* specs still prove that the core works without ns.L: they nil it
 * out themselves instead of relying on it never being loaded.
 */
const UI_FILES = [
  "AutoSpellQueue_Locale.lua",
  "AutoSpellQueue_Options.lua",
];

// Locale first (its ns.L is part of the frozen contract), Options last.
const ADDON_FILES = [UI_FILES[0], ...CORE_FILES, UI_FILES[1]];

/** Preferred spec order for readable output; anything else runs alphabetically. */
const SPEC_PRIORITY = ["spec_formula.lua", "spec_cvar.lua", "spec_core.lua"];

const filter = process.argv.slice(2).find((arg) => !arg.startsWith("-")) ?? null;
const listOnly = process.argv.includes("--list-specs");

/* ------------------------------------------------------------------- paths -- */

const slash = (p) => p.split(path.sep).join("/");

function specFiles() {
  const dir = path.join(ROOT, "tests");
  if (!fs.existsSync(dir)) return [];
  const found = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && /^spec_.*\.lua$/.test(entry.name))
    .map((entry) => `tests/${entry.name}`);
  const rank = (file) => {
    const index = SPEC_PRIORITY.indexOf(path.basename(file));
    return index === -1 ? SPEC_PRIORITY.length : index;
  };
  return found.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

/* ------------------------------------------------------------ lua plumbing -- */

function luaError(L) {
  const value = lua.lua_tostring(L, -1);
  const text = value === null ? "(非字符串错误对象)" : to_jsstring(value);
  lua.lua_pop(L, 1);
  return text;
}

/** Loads a chunk and runs it with no arguments. Returns null or an error text. */
function runFile(L, file) {
  const status = lauxlib.luaL_loadfile(L, to_luastring(slash(file)));
  if (status !== lua.LUA_OK) return luaError(L);
  const called = lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0);
  if (called !== lua.LUA_OK) return luaError(L);
  return null;
}

/** Loads a chunk and calls it with (addonName, nsTableOnStack). */
function runFileWithNs(L, file, nsIndex) {
  const status = lauxlib.luaL_loadfile(L, to_luastring(slash(file)));
  if (status !== lua.LUA_OK) return luaError(L);
  lua.lua_pushstring(L, to_luastring(ADDON_NAME));
  lua.lua_pushvalue(L, nsIndex);
  const called = lua.lua_pcall(L, 2, 0, 0);
  if (called !== lua.LUA_OK) return luaError(L);
  return null;
}

function setGlobalString(L, name, value) {
  lua.lua_pushstring(L, to_luastring(value));
  lua.lua_setglobal(L, to_luastring(name));
}

function setGlobalStringArray(L, name, values) {
  lua.lua_newtable(L);
  const tableIndex = lua.lua_gettop(L);
  values.forEach((value, index) => {
    lua.lua_pushstring(L, to_luastring(value));
    lua.lua_rawseti(L, tableIndex, index + 1);
  });
  lua.lua_setglobal(L, to_luastring(name));
}

/**
 * fengari has no working io.open, so the Lua specs cannot read files
 * themselves. Hand them the source text instead (used by the structural /
 * module-purity tests).
 */
function publishSources(L) {
  const files = [
    ...fs
      .readdirSync(ROOT, { withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith(".lua"))
      .map((entry) => entry.name),
    ...specFiles(),
  ];
  lua.lua_newtable(L);
  const tableIndex = lua.lua_gettop(L);
  for (const file of files) {
    lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(ROOT, file), "utf8")));
    lua.lua_setfield(L, tableIndex, to_luastring(file));
  }
  lua.lua_setglobal(L, to_luastring("ASQ_TEST_SOURCES"));
  // The manifest is metadata, not Lua, but the locale specs must be able to check
  // that ## Title / ## Title-zhCN / ## Title-zhTW agree with the locale table
  // (players would otherwise see two different names for one addon).
  const manifest = fs
    .readdirSync(ROOT)
    .filter((entry) => entry.endsWith(".toc"))
    .map((entry) => fs.readFileSync(path.join(ROOT, entry), "utf8"))
    .join("\n");
  lua.lua_pushstring(L, to_luastring(manifest));
  lua.lua_setglobal(L, to_luastring("ASQ_TEST_TOC"));
}

function fatal(message) {
  console.error(message);
  process.exit(1);
}

/* -------------------------------------------------------------------- main -- */

const specs = specFiles();
if (listOnly) {
  console.log(specs.length ? specs.join("\n") : "(没有 tests/spec_*.lua)");
  process.exit(0);
}

if (specs.length === 0) {
  fatal("run-tests.mjs: tests/ 下没有 spec_*.lua —— 没有任何测试会被执行");
}

console.log("AutoSpellQueue 测试运行器 (fengari / Lua 5.3)");
console.log(`  根目录 : ${ROOT}`);
console.log(`  被测文件 (${ADDON_FILES.length}):`);
for (const file of ADDON_FILES) {
  const full = path.join(ROOT, file);
  if (!fs.existsSync(full)) fatal(`  缺少运行期文件: ${file}`);
  console.log(`    ${file}  sha256=${sha256(full).slice(0, 16)}  ${fs.statSync(full).size}B`);
}
console.log(`  测试文件 (${specs.length}): ${specs.join(", ")}`);
if (filter) console.log(`  过滤   : ${filter}`);
console.log("");

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

setGlobalString(L, "ASQ_TEST_ROOT", slash(ROOT));
setGlobalStringArray(L, "ASQ_TEST_SPECS", specs);
publishSources(L);
if (filter) setGlobalString(L, "ASQ_TEST_FILTER", filter);

const stubError = runFile(L, path.join(ROOT, "tests", "wow_stub.lua"));
if (stubError) fatal(`tests/wow_stub.lua 加载失败:\n${stubError}`);

lua.lua_newtable(L);
const nsIndex = lua.lua_gettop(L);
for (const file of ADDON_FILES) {
  const error = runFileWithNs(L, path.join(ROOT, file), nsIndex);
  if (error) fatal(`${file} 加载失败:\n${error}`);
}
lua.lua_pushvalue(L, nsIndex);
lua.lua_setglobal(L, to_luastring("ASQ_TEST_NS"));

const runError = runFile(L, path.join(ROOT, "tests", "run.lua"));
if (runError) fatal(`tests/run.lua 执行失败:\n${runError}`);

lua.lua_getglobal(L, to_luastring("ASQ_TEST_EXIT_CODE"));
const rawCode = lua.lua_isnumber(L, -1) ? lua.lua_tonumber(L, -1) : 1;
lua.lua_pop(L, 1);
const code = Number.isFinite(rawCode) && rawCode === 0 ? 0 : 1;
process.exit(code);
