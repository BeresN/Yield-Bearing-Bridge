// BridgeBank ABI (source chain) - only the events and functions we need
export const bridgeBankAbi = [
  {
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
  {
    type: "function",
    name: "getDeposit",
    inputs: [{ name: "nonce", type: "uint256" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "depositor", type: "address" },
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "shares", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "sourceChainId", type: "uint256" },
          { name: "destinationChainId", type: "uint256" },
          { name: "timestamp", type: "uint256" },
          { name: "status", type: "uint8" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "depositNonce",
    inputs: [],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
] as const;

// DestBridge ABI (destination chain)
export const destBridgeAbi = [
  {
    type: "function",
    name: "mint",
    inputs: [
      {
        name: "message",
        type: "tuple",
        components: [
          { name: "depositor", type: "address" },
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "shares", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "sourceChainId", type: "uint256" },
          { name: "destinationChainId", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      },
      { name: "signature", type: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "usedNonces",
    inputs: [{ name: "nonce", type: "uint256" }],
    outputs: [{ type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "DOMAIN_SEPARATOR",
    inputs: [],
    outputs: [{ type: "bytes32" }],
    stateMutability: "view",
  },
] as const;

// EIP-712 types for BridgeMessage
export const bridgeMessageTypes = {
  BridgeMessage: [
    { name: "depositor", type: "address" },
    { name: "recipient", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "shares", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "sourceChainId", type: "uint256" },
    { name: "destinationChainId", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

// TypeScript types
export interface BridgeMessage {
  depositor: `0x${string}`;
  recipient: `0x${string}`;
  amount: bigint;
  shares: bigint;
  nonce: bigint;
  sourceChainId: bigint;
  destinationChainId: bigint;
  deadline: bigint;
}

export interface DepositEvent {
  depositor: `0x${string}`;
  recipient: `0x${string}`;
  amount: bigint;
  shares: bigint;
  nonce: bigint;
  destinationChainId: bigint;
  blockNumber: bigint;
  transactionHash: `0x${string}`;
}
