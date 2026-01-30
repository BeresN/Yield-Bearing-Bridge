# Yield-Bearing Bridge Relayer

TypeScript/viem relayer that watches for deposits on Sepolia and mints tokens on Arbitrum Sepolia.

## Security

This relayer uses **Foundry's encrypted keystore** instead of storing private keys in `.env` files:

- Keys are encrypted with scrypt at `~/.foundry/keystores/<name>`
- Password is prompted at startup (not stored anywhere)
- Same wallet used for `forge script --account`

## Setup

```bash
# Install dependencies
npm install

# Copy and configure environment
cp .env.example .env
# Edit .env with keystore account name and RPC URLs
```

## Configuration

The `.env` file requires:

- `KEYSTORE_ACCOUNT` - Name of Foundry keystore (from `cast wallet list`)
- `SEPOLIA_RPC_URL` - RPC endpoint for Sepolia
- `ARB_SEPOLIA_RPC_URL` - RPC endpoint for Arbitrum Sepolia
- `POLL_INTERVAL_MS` - (optional) Polling interval, defaults to 12000ms

### Managing Keystores

```bash
# List available keystores
cast wallet list

# Import existing private key
cast wallet import my-relayer --interactive

# Create new wallet
cast wallet new ~/.foundry/keystores/my-relayer
```

## Running

```bash
# Start the relayer (prompts for password)
npm start

# Watch mode (for development - DON'T use with password prompt)
npm run watch
```

You'll be prompted for your keystore password at startup.

## How it Works

1. **Loads** encrypted keystore and prompts for password
2. **Watches** BridgeBank on Sepolia for `Deposited` events
3. **Signs** EIP-712 typed data message with relayer key
4. **Submits** `mint()` transaction to DestBridge on Arbitrum Sepolia
5. **Tracks** processed nonces via on-chain `usedNonces` mapping

## Architecture

```
relayer/
├── src/
│   ├── index.ts      # Entry point
│   ├── config.ts     # Environment & chain configuration
│   ├── keystore.ts   # Foundry keystore decryption
│   ├── abi.ts        # Contract ABIs & types
│   └── relayer.ts    # Main relayer logic
├── package.json
├── tsconfig.json
└── .env.example
```
