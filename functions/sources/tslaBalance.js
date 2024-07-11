if (secrets.alpacaKey == "" || secrets.alpacaSecret == "") {
  throw Error("Alpaca keys not provided");
}

const alpacaRequest = Functions.makeHttpRequest({
  url: secrets.alpacaUrl,
  headers: {
    accept: "application/json",
    "APCA-API-KEY-ID": secrets.alpacaKey,
    "APCA-API-SECRET-KEY": secrets.alpacaSecret,
  },
});

const [response] = await Promise.all([alpacaRequest]);

const tslaBalance = response.data.market_value;
console.log(`TSLA Balance: ${tslaBalance}`);

return Functions.encodeUint256(Math.round(tslaBalance * 100));
