import { config as dotenvConfig } from "dotenv";
import { sepolia, arbitrumSepolia } from "viem/chains";

// Load environment variables
dotenvConfig();

// ============================================
// Environment Helpers
// ============================================

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

// ============================================
// Configuration
// ============================================

// Relayer configuration (loaded at startup)
export const config = {
  // Foundry keystore account name (from `cast wallet list`)
  keystoreAccount: requireEnv("KEYSTORE_ACCOUNT"),

  // RPC URLs
  sepoliaRpcUrl: requireEnv("SEPOLIA_RPC_URL"),
  arbSepoliaRpcUrl: requireEnv("ARB_SEPOLIA_RPC_URL"),

  // Polling interval (default 12 seconds)
  pollIntervalMs: parseInt(process.env.POLL_INTERVAL_MS || "12000"),

  // Chain configurations
  sourceChain: sepolia,
  destChain: arbitrumSepolia,
} as const;

// ============================================
// Contract Addresses
// ============================================

// Contract addresses from deployment files
import sepoliaDeployment from "../../deployments/sepolia.json" with { type: "json" };
import arbSepoliaDeployment from "../../deployments/arbitrum-sepolia.json" with { type: "json" };

export const contracts = {
  source: {
    chainId: sepoliaDeployment.chainId,
    bridgeBank: sepoliaDeployment.bridgeBank as `0x${string}`,
    usdc: sepoliaDeployment.usdc as `0x${string}`,
    vault: sepoliaDeployment.vault as `0x${string}`,
  },
  destination: {
    chainId: arbSepoliaDeployment.chainId,
    destBridge: arbSepoliaDeployment.destBridge as `0x${string}`,
    bridgedToken: arbSepoliaDeployment.bridgedToken as `0x${string}`,
    relayer: arbSepoliaDeployment.relayer as `0x${string}`,
  },
} as const;

// ============================================
// EIP-712 Domain
// ============================================

export const eip712Domain = {
  name: "YieldBearingBridge",
  version: "1",
  chainId: BigInt(contracts.destination.chainId),
  verifyingContract: contracts.destination.destBridge,
} as const;

// ============================================
// Log Configuration
// ============================================

console.log("Config loaded:");
console.log(`  Source Chain: ${config.sourceChain.name} (${contracts.source.chainId})`);
console.log(`  Dest Chain: ${config.destChain.name} (${contracts.destination.chainId})`);
console.log(`  BridgeBank: ${contracts.source.bridgeBank}`);
console.log(`  DestBridge: ${contracts.destination.destBridge}`);
console.log(`  Keystore Account: ${config.keystoreAccount}`);
