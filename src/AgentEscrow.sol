// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AgentEscrow
 * @notice Two-party escrow for agent-to-agent service payments.
 *
 * Flow:
 *   1. Buyer creates escrow, depositing SBC and naming a service provider
 *   2. Provider performs the service and calls complete() with a result hash
 *   3. Buyer calls approve() to release funds, or either party disputes
 *   4. After timeout, provider can force-release if buyer hasn't responded
 *
 * Note: Disputed funds remain locked. In production, add a dispute resolution
 * mechanism (e.g. trusted arbiter or mutual-consent split).
 *
 * Designed for AI agents on Radius — sub-second finality means escrow
 * creation and release happen nearly instantly.
 */
contract AgentEscrow {
    using SafeERC20 for IERC20;

    enum Status { Active, Completed, Approved, Disputed, Refunded }

    struct Escrow {
        address buyer;
        address provider;
        IERC20 token;
        uint256 amount;
        bytes32 serviceHash;      // Hash of the task description
        bytes32 resultHash;       // Hash of the service result (set by provider)
        uint256 deadline;         // Timestamp after which provider can force-release
        Status status;
    }

    uint256 public nextId;
    mapping(uint256 => Escrow) public escrows;

    event EscrowCreated(uint256 indexed id, address indexed buyer, address indexed provider, uint256 amount, bytes32 serviceHash);
    event ServiceCompleted(uint256 indexed id, bytes32 resultHash);
    event EscrowApproved(uint256 indexed id);
    event EscrowDisputed(uint256 indexed id, address by);
    event EscrowRefunded(uint256 indexed id);

    /**
     * @notice Create an escrow. Caller is the buyer.
     * @param provider Address of the service provider agent
     * @param token ERC-20 token to escrow (e.g. SBC)
     * @param amount Amount in token base units (e.g. 1_000_000 for 1 SBC)
     * @param serviceHash Hash of the task description for reference
     * @param timeoutSeconds Seconds until provider can force-release
     */
    function createEscrow(
        address provider,
        IERC20 token,
        uint256 amount,
        bytes32 serviceHash,
        uint256 timeoutSeconds
    ) external returns (uint256 id) {
        require(provider != address(0), "Invalid provider");
        require(amount > 0, "Amount must be > 0");

        id = nextId++;
        escrows[id] = Escrow({
            buyer: msg.sender,
            provider: provider,
            token: token,
            amount: amount,
            serviceHash: serviceHash,
            resultHash: bytes32(0),
            deadline: block.timestamp + timeoutSeconds,
            status: Status.Active
        });

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit EscrowCreated(id, msg.sender, provider, amount, serviceHash);
    }

    /**
     * @notice Provider marks service as completed with a result hash.
     */
    function complete(uint256 id, bytes32 resultHash) external {
        Escrow storage e = escrows[id];
        require(msg.sender == e.provider, "Only provider");
        require(e.status == Status.Active, "Not active");

        e.resultHash = resultHash;
        e.status = Status.Completed;
        emit ServiceCompleted(id, resultHash);
    }

    /**
     * @notice Buyer approves and releases funds to provider.
     */
    function approve(uint256 id) external {
        Escrow storage e = escrows[id];
        require(msg.sender == e.buyer, "Only buyer");
        require(e.status == Status.Completed, "Not completed");

        e.status = Status.Approved;
        e.token.safeTransfer(e.provider, e.amount);
        emit EscrowApproved(id);
    }

    /**
     * @notice Either party can dispute. Funds stay locked for manual resolution.
     */
    function dispute(uint256 id) external {
        Escrow storage e = escrows[id];
        require(msg.sender == e.buyer || msg.sender == e.provider, "Not a party");
        require(e.status == Status.Active || e.status == Status.Completed, "Cannot dispute");

        e.status = Status.Disputed;
        emit EscrowDisputed(id, msg.sender);
    }

    /**
     * @notice Buyer can refund if service was never completed and deadline passed.
     */
    function refund(uint256 id) external {
        Escrow storage e = escrows[id];
        require(msg.sender == e.buyer, "Only buyer");
        require(e.status == Status.Active, "Not active");
        require(block.timestamp >= e.deadline, "Deadline not reached");

        e.status = Status.Refunded;
        e.token.safeTransfer(e.buyer, e.amount);
        emit EscrowRefunded(id);
    }

    /**
     * @notice Provider can force-release after deadline if buyer hasn't responded.
     */
    function forceRelease(uint256 id) external {
        Escrow storage e = escrows[id];
        require(msg.sender == e.provider, "Only provider");
        require(e.status == Status.Completed, "Not completed");
        require(block.timestamp >= e.deadline, "Deadline not reached");

        e.status = Status.Approved;
        e.token.safeTransfer(e.provider, e.amount);
        emit EscrowApproved(id);
    }

}
