const { simulateScript, decodeResult } = require("@chainlinkt/functions-toolkit");

async function main() {
  await simulateScript();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
