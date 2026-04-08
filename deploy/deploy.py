#!/usr/bin/env python3
"""
Deploy agent contracts to Radius Testnet using radius-wallet-py.

Usage:
    pip install eth-account httpx
    export RADIUS_PRIVATE_KEY=0x...
    python deploy/deploy.py

Requires compiled artifacts in out/ (run `forge build` first).
"""

import json
import os
import sys

# Add parent dir so we can import radius_wallet if vendored alongside
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from radius_wallet import RadiusWallet, SBC_ADDRESS
except ImportError:
    print("radius_wallet not found. Install it:")
    print("  pip install git+https://github.com/radius-workshop/radius-wallet-py.git")
    sys.exit(1)


def load_artifact(name: str) -> dict:
    """Load compiled contract artifact from Foundry's out/ directory."""
    path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "out",
        f"{name}.sol",
        f"{name}.json",
    )
    with open(path) as f:
        return json.load(f)


def deploy(wallet: RadiusWallet, name: str, constructor_types=None, constructor_args=None):
    """Deploy a contract and print the result."""
    print(f"\nDeploying {name}...")
    artifact = load_artifact(name)
    bytecode = artifact["bytecode"]["object"]

    result = wallet.deploy_contract(bytecode, constructor_types, constructor_args)

    if wallet.tx_succeeded(result["receipt"]):
        print(f"  Address: {result['address']}")
        print(f"  Tx:      {result['tx_hash']}")
        print(f"  Explorer: {wallet.explorer_url(result['tx_hash'])}")
    else:
        print(f"  FAILED — tx: {result['tx_hash']}")

    return result


def main():
    wallet = RadiusWallet.from_env()
    print(f"Deployer: {wallet.address}")
    print(f"SBC balance: {wallet.get_sbc_balance()} SBC")
    print(f"RUSD balance: {wallet.get_rusd_balance()} RUSD")

    # Deploy AgentEscrow (no constructor args)
    deploy(wallet, "AgentEscrow")

    # Deploy BountyBoard (no constructor args)
    deploy(wallet, "BountyBoard")

    # Deploy PayPerQuery (token address + price per query)
    # Price: 100_000 = 0.1 SBC (6 decimals)
    deploy(
        wallet,
        "PayPerQuery",
        constructor_types=["address", "uint256"],
        constructor_args=[SBC_ADDRESS, 100_000],
    )

    # Deploy PaymentSplitter (token + payees + shares)
    # Example: 3 agents splitting revenue 50/30/20
    # Replace these with real agent wallet addresses!
    example_payees = [
        wallet.address,  # Agent A (you) — 50%
        "0x0000000000000000000000000000000000000001",  # Agent B — 30%
        "0x0000000000000000000000000000000000000002",  # Agent C — 20%
    ]
    example_shares = [50, 30, 20]
    deploy(
        wallet,
        "PaymentSplitter",
        constructor_types=["address", "address[]", "uint256[]"],
        constructor_args=[SBC_ADDRESS, example_payees, example_shares],
    )

    print("\nDone! All contracts deployed to Radius Testnet.")


if __name__ == "__main__":
    main()
