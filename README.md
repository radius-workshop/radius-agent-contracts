# radius-agent-contracts

Smart contracts for agent-to-agent commerce on the [Radius network](https://radiustech.xyz). Designed for AI agents that need to coordinate payments, escrow services, post bounties, meter API usage, and share revenue.

Built with [Foundry](https://book.getfoundry.sh/). All contracts use SBC (ERC-20 stablecoin) as the payment token.

## Contracts

### AgentEscrow

Two-party escrow for agent services. Buyer deposits SBC, provider performs a service, buyer approves to release funds. Includes timeout-based force-release and dispute flagging. (In production, add a dispute resolution mechanism.)

**Use case:** Agent A pays Agent B to perform a task. Funds are locked until the work is verified.

### BountyBoard

Open task marketplace. Any agent can post bounties with SBC rewards, and any agent can claim, complete, and get paid.

**Use case:** An orchestrator agent posts tasks with rewards. Specialized agents browse, claim, and complete bounties autonomously.

### PayPerQuery

Metered API billing. Consumers pre-fund a balance, each query deducts a micro-fee. Providers watch `QueryPaid` events and serve responses off-chain.

**Use case:** An AI data agent charges 0.1 SBC per query. Radius's sub-second finality makes per-request billing practical.

### PaymentSplitter

Revenue sharing for agent teams. Deposits are automatically split among payees by their share weights.

**Use case:** Three agents collaborate — orchestrator (50%), researcher (30%), writer (20%). Revenue splits automatically.

## Quick Start

```bash
# Install Foundry if needed: https://book.getfoundry.sh/getting-started/installation

# Build
forge build

# Test (62 tests across all contracts)
forge test -v

# Deploy to Radius Testnet with Foundry
export RADIUS_PRIVATE_KEY=0x...
forge create src/AgentEscrow.sol:AgentEscrow \
  --rpc-url https://rpc.testnet.radiustech.xyz \
  --private-key $RADIUS_PRIVATE_KEY
```

## Deploy Scripts

### Python

```bash
pip install eth-account httpx
# or: pip install git+https://github.com/radius-workshop/radius-wallet-py.git
export RADIUS_PRIVATE_KEY=0x...
export PAYMENT_SPLITTER_PAYEES=0xYourAddress,0xCollaboratorAddress
export PAYMENT_SPLITTER_SHARES=70,30
forge build
python deploy/deploy.py
```

### TypeScript

```bash
npm install viem
export RADIUS_PRIVATE_KEY=0x...
export PAYMENT_SPLITTER_PAYEES=0xYourAddress,0xCollaboratorAddress
export PAYMENT_SPLITTER_SHARES=70,30
forge build
npx tsx deploy/deploy.ts
```

## Interacting with Deployed Contracts

### From Python (using radius-wallet-py)

```python
from radius_wallet import RadiusWallet

wallet = RadiusWallet.from_env()

# Create an escrow
tx = wallet.send_contract_tx(
    "0xDeployedEscrowAddress",
    "createEscrow(address,address,uint256,bytes32,uint256)",
    arg_types=["address", "address", "uint256", "bytes32", "uint256"],
    args=[
        "0xProviderAddress",        # provider
        "0x33ad...4Fb",              # SBC token
        1_000_000,                   # 1 SBC (6 decimals)
        b'\x00' * 32,               # service hash
        3600,                        # 1 hour timeout
    ],
)
receipt = wallet.wait_for_tx(tx)
```

### From TypeScript (using viem)

```typescript
import { RadiusWallet, SBC_ADDRESS } from "radius-wallet-ts";
import { parseAbi } from "viem";

const wallet = RadiusWallet.fromEnv();

const hash = await wallet.writeContract(
  "0xDeployedEscrowAddress",
  parseAbi(["function createEscrow(address,address,uint256,bytes32,uint256)"]),
  "createEscrow",
  [providerAddress, SBC_ADDRESS, 1_000_000n, "0x" + "00".repeat(32), 3600n]
);
```

### From Foundry CLI

```bash
# Read a bounty
cast call 0xBountyBoardAddress "getBounty(uint256)" 0 \
  --rpc-url https://rpc.testnet.radiustech.xyz

# Post a bounty (after approving SBC spend)
cast send 0xBountyBoardAddress \
  "postBounty(address,uint256,string,uint256)" \
  0x33ad...4Fb 1000000 "Analyze dataset" $(date -v+1d +%s) \
  --rpc-url https://rpc.testnet.radiustech.xyz \
  --private-key $RADIUS_PRIVATE_KEY
```

## Network Details

| | Testnet | Mainnet |
|--|---------|---------|
| RPC | `https://rpc.testnet.radiustech.xyz` | `https://rpc.radiustech.xyz` |
| Chain ID | 72344 | 723487 |
| SBC Token | `0x33ad9e4BD16B69B5BFdED37D8B5D9fF9aba014Fb` | Same |
| SBC Decimals | 6 | 6 |

**Important:** Before interacting with contracts that transfer SBC, the caller must approve the contract to spend their tokens:

```bash
cast send 0x33ad9e4BD16B69B5BFdED37D8B5D9fF9aba014Fb \
  "approve(address,uint256)" \
  0xContractAddress 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
  --rpc-url https://rpc.testnet.radiustech.xyz \
  --private-key $RADIUS_PRIVATE_KEY
```

## Related Repos

- **[radius-wallet-py](https://github.com/radius-workshop/radius-wallet-py)** — Python wallet library
- **[radius-wallet-ts](https://github.com/radius-workshop/radius-wallet-ts)** — TypeScript wallet library
- **[radius-agent-template](https://github.com/radius-workshop/radius-agent-template)** — Minimal NEST payment agent

---

> ⚠️ **Demo code — not production-ready.** Provided as-is, without warranty, and may contain known, unpatched vulnerabilities (including in dependencies). If you reuse it, run your own security and supply-chain scans and patch before deploying.
