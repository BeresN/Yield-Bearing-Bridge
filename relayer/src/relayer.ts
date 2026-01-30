import {
  createPublicClient,
  createWalletClient,
  http,
  type PublicClient,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { config, contracts, eip712Domain } from "./config.js";
import { loadFoundryKeystore } from "./keystore.js";
import {
  bridgeBankAbi,
  destBridgeAbi,
  bridgeMessageTypes,
  type BridgeMessage,
  type DepositEvent,
} from "./abi.js";

export class BridgeRelayer {
  private sourceClient: PublicClient;
  private destClient: PublicClient;
  private walletClient!: WalletClient;
  private relayerAccount!: ReturnType<typeof privateKeyToAccount>;
  private lastProcessedBlock: bigint = 0n;
  private isRunning: boolean = false;

  constructor() {
    // Create read-only clients (wallet initialized in init())
    this.sourceClient = createPublicClient({
      chain: config.sourceChain,
      transport: http(config.sepoliaRpcUrl),
    });

    this.destClient = createPublicClient({
      chain: config.destChain,
      transport: http(config.arbSepoliaRpcUrl),
    });
  }

  /**
   * Initializes the relayer by loading the keystore
   * Must be called before start()
   */
  async init(): Promise<void> {
    // Load private key from Foundry keystore (prompts for password)
    const privateKey = await loadFoundryKeystore(config.keystoreAccount);

    // Setup relayer account
    this.relayerAccount = privateKeyToAccount(privateKey);

    this.walletClient = createWalletClient({
      account: this.relayerAccount,
      chain: config.destChain,
      transport: http(config.arbSepoliaRpcUrl),
    });

    console.log(`Relayer address: ${this.relayerAccount.address}`);

    // Verify this matches the expected relayer on DestBridge
    if (this.relayerAccount.address.toLowerCase() !== contracts.destination.relayer.toLowerCase()) {
      console.warn(`WARNING: Wallet address doesn't match DestBridge relayer!`);
      console.warn(`  Wallet: ${this.relayerAccount.address}`);
      console.warn(`  Expected: ${contracts.destination.relayer}`);
    }
  }

  /**
   * Starts the relayer - polls for new deposits and processes them
   */
  async start(): Promise<void> {
    if (!this.relayerAccount) {
      throw new Error("Relayer not initialized. Call init() first.");
    }

    console.log("\nStarting Bridge Relayer...\n");

    // Get the current block as starting point
    this.lastProcessedBlock = await this.sourceClient.getBlockNumber();
    console.log(`Starting from block: ${this.lastProcessedBlock}`);

    this.isRunning = true;

    // Main polling loop
    while (this.isRunning) {
      try {
        await this.pollForDeposits();
      } catch (error) {
        console.error("Error polling for deposits:", error);
      }

      // Wait before next poll
      await this.sleep(config.pollIntervalMs);
    }
  }

  /**
   * Stops the relayer gracefully
   */
  stop(): void {
    console.log("\nStopping relayer...");
    this.isRunning = false;
  }

  /**
   * Polls for new Deposited events and processes them
   */
  private async pollForDeposits(): Promise<void> {
    const currentBlock = await this.sourceClient.getBlockNumber();

    if (currentBlock <= this.lastProcessedBlock) {
      return; // No new blocks
    }

    console.log(`\nChecking blocks ${this.lastProcessedBlock + 1n} to ${currentBlock}...`);

    // Get Deposited events
    const logs = await this.sourceClient.getLogs({
      address: contracts.source.bridgeBank,
      event: {
        type: "event",
        name: "Deposited",
        inputs: [
          { name: "depositor", type: "address", indexed: true },
          { name: "recipient", type: "address", indexed: true },
          { name: "amount", type: "uint256", indexed: false },
          { name: "shares", type: "uint256", indexed: false },
          { name: "nonce", type: "uint256", indexed: true },
          { name: "destinationChainId", type: "uint256", indexed: false },
        ],
      },
      fromBlock: this.lastProcessedBlock + 1n,
      toBlock: currentBlock,
    });

    if (logs.length > 0) {
      console.log(`Found ${logs.length} new deposit(s)`);

      for (const log of logs) {
        const deposit: DepositEvent = {
          depositor: log.args.depositor!,
          recipient: log.args.recipient!,
          amount: log.args.amount!,
          shares: log.args.shares!,
          nonce: log.args.nonce!,
          destinationChainId: log.args.destinationChainId!,
          blockNumber: log.blockNumber,
          transactionHash: log.transactionHash,
        };

        await this.processDeposit(deposit);
      }
    }

    this.lastProcessedBlock = currentBlock;
  }

  /**
   * Processes a single deposit - signs message and submits mint tx
   */
  private async processDeposit(deposit: DepositEvent): Promise<void> {
    console.log(`\nProcessing deposit nonce: ${deposit.nonce}`);
    console.log(`  From: ${deposit.depositor}`);
    console.log(`  To: ${deposit.recipient}`);
    console.log(`  Amount: ${deposit.amount}`);

    // Check if already minted on destination
    const alreadyMinted = await this.destClient.readContract({
      address: contracts.destination.destBridge,
      abi: destBridgeAbi,
      functionName: "usedNonces",
      args: [deposit.nonce],
    });

    if (alreadyMinted) {
      console.log(`  Already minted, skipping`);
      return;
    }

    // Create bridge message with 1 hour deadline
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const message: BridgeMessage = {
      depositor: deposit.depositor,
      recipient: deposit.recipient,
      amount: deposit.amount,
      shares: deposit.shares,
      nonce: deposit.nonce,
      sourceChainId: BigInt(contracts.source.chainId),
      destinationChainId: BigInt(contracts.destination.chainId),
      deadline,
    };

    // Sign the message using EIP-712
    console.log(`  Signing message...`);
    const signature = await this.walletClient.signTypedData({
      account: this.relayerAccount,
      domain: eip712Domain,
      types: bridgeMessageTypes,
      primaryType: "BridgeMessage",
      message: {
        depositor: message.depositor,
        recipient: message.recipient,
        amount: message.amount,
        shares: message.shares,
        nonce: message.nonce,
        sourceChainId: message.sourceChainId,
        destinationChainId: message.destinationChainId,
        deadline: message.deadline,
      },
    });

    // Submit mint transaction
    console.log(`  Submitting mint transaction...`);
    try {
      const hash = await this.walletClient.writeContract({
        chain: config.destChain,
        account: this.relayerAccount,
        address: contracts.destination.destBridge,
        abi: destBridgeAbi,
        functionName: "mint",
        args: [message, signature],
      });

      console.log(`  Mint tx submitted: ${hash}`);

      // Wait for confirmation
      const receipt = await this.destClient.waitForTransactionReceipt({ hash });
      console.log(`  Confirmed in block: ${receipt.blockNumber}`);
    } catch (error: any) {
      console.error(`  Mint failed:`, error.message || error);
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
