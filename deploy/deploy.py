#!/usr/bin/env python3
"""
Deploy agent contracts to Radius Testnet using radius-wallet-py.

Usage:
    pip install eth-account httpx
    export RADIUS_PRIVATE_KEY=0x...
    export PAYMENT_SPLITTER_PAYEES=0xYourAddress,0xCollaboratorAddress
    export PAYMENT_SPLITTER_SHARES=70,30
    python deploy/deploy.py

Requires compiled artifacts in out/ (run `forge build` first).
"""

import json
import os
import re
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


_ADDRESS_RE = re.compile(r"^0x[0-9a-fA-F]{40}$")


def _required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Missing {name}. Set it before running deploy.")
    return value


def _parse_payees() -> list[str]:
    raw = _required_env("PAYMENT_SPLITTER_PAYEES")
    payees = [p.strip() for p in raw.split(",") if p.strip()]
    if not payees:
        raise ValueError("PAYMENT_SPLITTER_PAYEES must contain at least one address.")
    if len({p.lower() for p in payees}) != len(payees):
        raise ValueError("PAYMENT_SPLITTER_PAYEES contains duplicate addresses.")
    for payee in payees:
        if not _ADDRESS_RE.match(payee):
            raise ValueError(f"Invalid payee address: {payee}")
    return payees


def _parse_shares(expected_len: int) -> list[int]:
    raw = _required_env("PAYMENT_SPLITTER_SHARES")
    shares = []
    for value in [v.strip() for v in raw.split(",") if v.strip()]:
        if not value.isdigit():
            raise ValueError(f"Invalid share value: {value}")
        share = int(value)
        if share <= 0:
            raise ValueError("Shares must be positive integers.")
        shares.append(share)

    if len(shares) != expected_len:
        raise ValueError(
            "PAYMENT_SPLITTER_SHARES length must match PAYMENT_SPLITTER_PAYEES length."
        )
    return shares


def main():
    wallet = RadiusWallet.from_env()
    splitter_payees = _parse_payees()
    splitter_shares = _parse_shares(len(splitter_payees))

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

    # Deploy PaymentSplitter (token + payees + shares) using explicit env config.
    deploy(
        wallet,
        "PaymentSplitter",
        constructor_types=["address", "address[]", "uint256[]"],
        constructor_args=[SBC_ADDRESS, splitter_payees, splitter_shares],
    )

    print("\nDone! All contracts deployed to Radius Testnet.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as e:
        print(f"Configuration error: {e}")
        print("Set PAYMENT_SPLITTER_PAYEES and PAYMENT_SPLITTER_SHARES before deploy.")
        sys.exit(1)
