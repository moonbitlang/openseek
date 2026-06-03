import { promises as fs } from "node:fs";
import path from "node:path";

const FUNCTION_NAME = /^[a-z_][A-Za-z0-9_]*$/;

async function main() {
  const args = parseProgramArgs(process.argv.slice(2));
  const base = path.basename(args.input);
  const functionName = functionNameFromBase(base);
  const markdown = await fs.readFile(args.input, "utf8");
  const source = generatedSource({ base, functionName, markdown });
  const tmp = `${args.output}.tmp`;
  await fs.writeFile(tmp, source, "utf8");
  await fs.rename(tmp, args.output);
}

function parseProgramArgs(args) {
  if (args.length !== 2) {
    fail("usage: md_to_mbt_string <input> <output>");
  }
  return {
    input: args[0],
    output: args[1],
  };
}

function functionNameFromBase(base) {
  let name;
  if (base.endsWith(".mbt.md")) {
    name = base.slice(0, -".mbt.md".length);
  } else if (base.endsWith(".md")) {
    name = base.slice(0, -".md".length);
  } else {
    fail(`md_to_mbt_string: input must end in .md or .mbt.md: ${base}`);
  }
  if (!FUNCTION_NAME.test(name)) {
    fail(
      `md_to_mbt_string: input basename is not a MoonBit function name: ${name}`,
    );
  }
  return name;
}

function generatedSource({ base, functionName, markdown }) {
  const lines = markdown.split("\n");
  if (markdown.endsWith("\n")) {
    lines.pop();
  }

  const out = [
    `// Generated from ${base} by moon dev_build. DO NOT EDIT.`,
    "///|",
    `fn ${functionName}() -> String {`,
    "  (",
  ];
  for (const line of lines) {
    out.push(`    #|${line}`);
  }
  out.push("  )", "}");
  return `${out.join("\n")}\n`;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

main().catch((error) => {
  fail(error instanceof Error ? error.message : String(error));
});
