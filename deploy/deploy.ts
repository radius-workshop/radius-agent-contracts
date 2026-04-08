/**
 * Deploy agent contracts to Radius Testnet using radius-wallet-ts.
 *
 * Usage:
 *   forge build
 *   export RADIUS_PRIVATE_KEY=0x...
 *   npx tsx deploy/deploy.ts
 *
 * Requires compiled artifacts in out/ (run `forge build` first).
 */

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

// If using the wallet library as a local import:
// import { RadiusWallet, SBC_ADDRESS } from "radius-wallet-ts";
//
// For now, we inline the constants and use viem directly:
import {
  createPublicClient,
  createWalletClient,
  http,
  defineChain,
  formatUnits,
  type Abi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

const SBC_ADDRESS = "0x33ad9e4BD16B69B5BFdED37D8B5D9fF9aba014Fb";
const SBC_DECIMALS = 6;

const radiusTestnet = defineChain({
  id: 72344,
  name: "Radius Testnet",
  nativeCurrency: { name: "RUSD", symbol: "RUSD", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.testnet.radiustech.xyz"] },
  },
  blockExplorers: {
    default: {
      name: "Radius Explorer",
      url: "https://testnet.radiustech.xyz",
    },
  },
});

const key = process.env.RADIUS_PRIVATE_KEY;
if (!key) {
  console.error("Set RADIUS_PRIVATE_KEY");
  process.exit(1);
}

const account = privateKeyToAccount(key as `0x${string}`);
const transport = http(radiusTestnet.rpcUrls.default.http[0]);
const publicClient = createPublicClient({ chain: radiusTestnet, transport });
const walletClient = createWalletClient({
  account,
  chain: radiusTestnet,
  transport,
});

function loadArtifact(name: string) {
  const path = join(ROOT, "out", `${name}.sol`, `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8"));
}

async function deploy(name: string, args?: unknown[]) {
  console.log(`\nDeploying ${name}...`);
  const artifact = loadArtifact(name);
  const bytecode = artifact.bytecode.object as `0x${string}`;
  const abi = artifact.abi as Abi;

  const hash = await walletClient.deployContract({
    abi,
    bytecode,
    args: args ?? [],
    chain: radiusTestnet,
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  if (receipt.contractAddress) {
    console.log(`  Address: ${receipt.contractAddress}`);
    console.log(`  Tx:      ${hash}`);
    console.log(
      `  Explorer: https://testnet.radiustech.xyz/tx/${hash}`
    );
  } else {
    console.log(`  FAILED — tx: ${hash}`);
  }
  return receipt;
}

async function main() {
  console.log(`Deployer: ${account.address}`);

  // Deploy AgentEscrow
  await deploy("AgentEscrow");

  // Deploy BountyBoard
  await deploy("BountyBoard");

  // Deploy PayPerQuery (token, pricePerQuery)
  await deploy("PayPerQuery", [SBC_ADDRESS, 100_000n]);

  // Deploy PaymentSplitter (token, payees, shares)
  await deploy("PaymentSplitter", [
    SBC_ADDRESS,
    [
      account.address,
      "0x0000000000000000000000000000000000000001",
      "0x0000000000000000000000000000000000000002",
    ],
    [50n, 30n, 20n],
  ]);

  console.log("\nDone! All contracts deployed to Radius Testnet.");
}

main().catch(console.error);
