#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

function optionalPayloadEnv() {
  try {
    const raw = fs.readFileSync(0, "utf8").trim();
    if (raw.length === 0) {
      return {};
    }
    return JSON.parse(raw).env ?? {};
  } catch {
    return {};
  }
}

function envValue(env, name) {
  return env[name] ?? process.env[name] ?? "";
}

function commandName(command) {
  const first = String(command).trim().split(/\s+/)[0] ?? "";
  return path.basename(first).toLowerCase().replace(/\.(exe|cmd|bat)$/u, "");
}

function pathEntries(env) {
  const raw = envValue(env, "PATH");
  if (raw.length === 0) {
    return [];
  }
  return raw.split(path.delimiter).filter((entry) => entry.length > 0);
}

function commandExists(env, command) {
  const isWindows = process.platform === "win32" || env.OS === "Windows_NT";
  const extensions = isWindows
    ? ["", ".exe", ".cmd", ".bat"]
    : [""];
  for (const directory of pathEntries(env)) {
    for (const extension of extensions) {
      if (fs.existsSync(path.join(directory, command + extension))) {
        return true;
      }
    }
  }
  return false;
}

function configuredCompiler(env) {
  for (const name of ["MOON_CC", "MOONBIT_CC", "MBC_CC", "CC", "CXX"]) {
    const value = envValue(env, name).trim();
    if (value.length > 0) {
      return value;
    }
  }
  return "";
}

function linkStyleFromCompiler(command) {
  const name = commandName(command);
  if (name === "cl" || name === "clang-cl") {
    return "msvc-driver";
  }
  if (name === "gcc" || name === "g++" || name.includes("mingw")) {
    return "mingw-driver";
  }
  if (name === "clang" || name === "clang++" || name === "cc" || name === "c++") {
    return "clang-driver";
  }
  return "";
}

function hasMsvcEnvironment(env) {
  return [
    "VCINSTALLDIR",
    "VCToolsInstallDir",
    "VisualStudioVersion",
    "INCLUDE",
    "LIB",
  ].some((name) => envValue(env, name).trim().length > 0);
}

function hasMsvcToolchain(env) {
  // Moon discovers MSVC through vswhere even when the shell carries no VC
  // environment, so a plain PowerShell prompt must reach the same verdict.
  const programFilesX86 = envValue(env, "ProgramFiles(x86)").trim();
  if (programFilesX86.length === 0) {
    return false;
  }
  const vswhere = path.join(
    programFilesX86,
    "Microsoft Visual Studio",
    "Installer",
    "vswhere.exe",
  );
  if (!fs.existsSync(vswhere)) {
    return false;
  }
  try {
    const installations = execFileSync(vswhere, [
      "-latest",
      "-products", "*",
      "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
      "-property", "installationPath",
    ], { encoding: "utf8" });
    return installations.trim().length > 0;
  } catch {
    return false;
  }
}

function detectedLinkStyle(env) {
  const explicit = envValue(env, "OPENSEEK_DESKTOP_LINK_STYLE").trim().toLowerCase();
  switch (explicit) {
    case "clang":
    case "clang-driver":
      return "clang-driver";
    case "msvc":
    case "msvc-driver":
    case "clang-cl":
    case "cl":
      return "msvc-driver";
    case "mingw":
    case "gcc":
    case "mingw-driver":
      return "mingw-driver";
    default:
      break;
  }
  const compiler = configuredCompiler(env);
  const compilerStyle = linkStyleFromCompiler(compiler);
  if (compilerStyle.length > 0) {
    return compilerStyle;
  }
  const isWindows = process.platform === "win32" || env.OS === "Windows_NT";
  if (isWindows && (hasMsvcEnvironment(env) || hasMsvcToolchain(env))) {
    return "msvc-driver";
  }
  if (commandExists(env, "clang")) {
    return "clang-driver";
  }
  if (commandExists(env, "clang-cl") || commandExists(env, "cl")) {
    return "msvc-driver";
  }
  if (commandExists(env, "gcc") || commandExists(env, "g++")) {
    return "mingw-driver";
  }
  return "clang-driver";
}

function windowsGuiLinkFlags(env) {
  switch (detectedLinkStyle(env)) {
    case "msvc-driver":
      return "/link /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup";
    case "mingw-driver":
      return "-mwindows";
    case "clang-driver":
    default:
      return "-Wl,/SUBSYSTEM:WINDOWS -Wl,/ENTRY:mainCRTStartup";
  }
}

function main() {
  const env = optionalPayloadEnv();
  const isWindows = process.platform === "win32" || env.OS === "Windows_NT";
  if (!isWindows) {
    process.stdout.write(JSON.stringify({ link_configs: [] }));
    return;
  }
  process.stdout.write(JSON.stringify({
    link_configs: [
      {
        package: "openseek_desktop",
        link_flags: windowsGuiLinkFlags(env),
      },
    ],
  }));
}

main();
