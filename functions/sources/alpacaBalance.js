if (secrets.alpacaKey == "" || secrets.alpacaSecret == "") {
  throw Error("Alpaca keysnot provided");
}

const alpacaRequest = Functions.makeHttpRequest({
  url: "https://paper-api.alpaca.markets/v2/positions/TSLA",
  headers: {
    accept: "application/json",
    "APCA-API-KEY-ID": "PK3G88XBEWFMUV8TKBOM",
    "APCA-API-SECRET-KEY": "pJn7TymJ1qz52CHTE8DuAHLJntDpKqJpG4lO1eRO",
  },
});

const [response] = await Promise.all([alpacaRequest]);

const tslaBalance = response.data.market_value;
console.log(`TSLA Balance: ${tslaBalance}`);

return Functions.encodeUint256(Math.round(tslaBalance * 100));
