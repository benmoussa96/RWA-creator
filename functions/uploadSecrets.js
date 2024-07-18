const { SecretsManager } = require("@chainlink/functions-toolkit");
const ethers = require("ethers");

async function uploadSecrets() {
  const privateKey = process.env.PRIVATE_KEY;
  const rpcUrl = process.env.SEPOLIA_RPC_URL;

  const functionsRouterAddress = "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0";
  const donId = "fun-ethereum-sepolia-1";
  const gatewayUrls = [
    "https://01.functions-gateway.testnet.chain.link/",
    "https://02.functions-gateway.testnet.chain.link/",
  ];

  const alpacaEndpoint = "/positions/TSLA";

  const secrets = {
    alpacaKey: process.env.ALPACA_API_KEY ?? "",
    alpacaSecret: process.env.ALPACA_SECRET_KEY ?? "",
    alpacaUrl: process.env.ALPACA_API_URL + alpacaEndpoint ?? "",
  };

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey);
  const signer = wallet.connect(provider);

  const secretsManager = new SecretsManager({
    signer,
    functionsRouterAddress,
    donId,
  });
  await secretsManager.initialize();

  const encryptedSecretsResult = await secretsManager.encryptSecrets(secrets);
  const slotId = 0;
  const minutesUntilExpiration = 1440;

  const uploadResult = await secretsManager.uploadEncryptedSecretsToDON({
    encryptedSecretsHexstring: encryptedSecretsResult.encryptedSecrets,
    gatewayUrls,
    slotId,
    minutesUntilExpiration,
  });

  if (!uploadResult.success) {
    throw new Error(`Failed to upload secrets: ${uploadResult.errorMessage}`);
  }

  console.log(`\n✅ Secrets uploaded successfully. Response: ${uploadResult}`);
  console.log(`Secrets version: ${parseInt(uploadResult.version)}`);
}

uploadSecrets().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
