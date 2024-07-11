const tslaBalanceRequestConfig = require("../configs/tslaMintConfig.js");
const { simulateScript, decodeResult } = require("@chainlink/functions-toolkit");

async function main() {
  const { responseBytesHexstring, errorString, capturedTerminalOutput } = await simulateScript(
    tslaBalanceRequestConfig
  );

  if (responseBytesHexstring) {
    console.log(
      `TSLA Balance Response: ${decodeResult(
        responseBytesHexstring,
        tslaBalanceRequestConfig.expectedReturnType
      )}\n`
    );
  }

  if (errorString) {
    console.log(`TSLA Balance Error: ${errorString}\n`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
