const fs = require("fs");
const { Location, ReturnType, CodeLanguage } = require("@chainlink/functions-toolkit");

const alpacaEndpoint = "/positions/TSLA";

const tslaBalanceRequestConfig = {
  source: fs.readFileSync("./functions/sources/tslaBalance.js").toString(),
  codeLocation: Location.Inline,
  secrets: {
    alpacaKey: process.env.ALPACA_API_KEY ?? "",
    alpacaSecret: process.env.ALPACA_SECRET_KEY ?? "",
    alpacaUrl: process.env.ALPACA_API_URL + alpacaEndpoint ?? "",
  },
  secretsLocation: Location.DONHosted,
  args: [],
  codeLanguage: CodeLanguage.JavaScript,
  expectedReturnType: ReturnType.uint256,
};

module.exports = tslaBalanceRequestConfig;
