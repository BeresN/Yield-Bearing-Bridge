import { BridgeRelayer } from "./relayer.js";

async function main() {
  console.log("╔═══════════════════════════════════════════════════╗");
  console.log("║       Yield-Bearing Bridge Relayer                ║");
  console.log("║       Sepolia → Arbitrum Sepolia                  ║");
  console.log("╚═══════════════════════════════════════════════════╝");

  const relayer = new BridgeRelayer();

  // Initialize (loads keystore with password prompt)
  await relayer.init();

  // Handle graceful shutdown
  process.on("SIGINT", () => {
    relayer.stop();
    process.exit(0);
  });

  process.on("SIGTERM", () => {
    relayer.stop();
    process.exit(0);
  });

  // Start the relayer
  await relayer.start();
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
