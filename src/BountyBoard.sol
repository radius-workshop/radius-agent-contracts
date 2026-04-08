// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BountyBoard
 * @notice Open task marketplace for AI agents. Any agent can post bounties,
 *         any agent can claim and complete them.
 *
 * Flow:
 *   1. Poster calls postBounty() with description + SBC reward + deadline
 *   2. Worker calls claimBounty() to start working
 *   3. Worker calls submitWork() with a result hash
 *   4. Poster calls approveBounty() to release reward
 *   5. After deadline, poster can reclaim uncompleted bounties
 */
contract BountyBoard {
    using SafeERC20 for IERC20;

    enum Status { Open, Claimed, Submitted, Completed, Expired }

    struct Bounty {
        address poster;
        address worker;
        IERC20 token;
        uint256 reward;
        string description;
        bytes32 resultHash;
        uint256 deadline;
        Status status;
    }

    uint256 public nextId;
    mapping(uint256 => Bounty) public bounties;

    event BountyPosted(uint256 indexed id, address indexed poster, uint256 reward, string description);
    event BountyClaimed(uint256 indexed id, address indexed worker);
    event WorkSubmitted(uint256 indexed id, bytes32 resultHash);
    event BountyCompleted(uint256 indexed id, address indexed worker, uint256 reward);
    event BountyExpired(uint256 indexed id);

    /**
     * @notice Post a new bounty. Caller deposits the reward.
     */
    function postBounty(
        IERC20 token,
        uint256 reward,
        string calldata description,
        uint256 deadlineTimestamp
    ) external returns (uint256 id) {
        require(reward > 0, "Reward must be > 0");
        require(deadlineTimestamp > block.timestamp, "Deadline must be in the future");

        id = nextId++;
        bounties[id] = Bounty({
            poster: msg.sender,
            worker: address(0),
            token: token,
            reward: reward,
            description: description,
            resultHash: bytes32(0),
            deadline: deadlineTimestamp,
            status: Status.Open
        });

        token.safeTransferFrom(msg.sender, address(this), reward);
        emit BountyPosted(id, msg.sender, reward, description);
    }

    /**
     * @notice Claim a bounty to start working on it. One worker at a time.
     */
    function claimBounty(uint256 id) external {
        Bounty storage b = bounties[id];
        require(b.status == Status.Open, "Not open");
        require(block.timestamp < b.deadline, "Expired");

        b.worker = msg.sender;
        b.status = Status.Claimed;
        emit BountyClaimed(id, msg.sender);
    }

    /**
     * @notice Submit work with a result hash (e.g. IPFS CID, data hash).
     */
    function submitWork(uint256 id, bytes32 resultHash) external {
        Bounty storage b = bounties[id];
        require(msg.sender == b.worker, "Only assigned worker");
        require(b.status == Status.Claimed, "Not claimed");

        b.resultHash = resultHash;
        b.status = Status.Submitted;
        emit WorkSubmitted(id, resultHash);
    }

    /**
     * @notice Poster approves the work and releases the reward.
     */
    function approveBounty(uint256 id) external {
        Bounty storage b = bounties[id];
        require(msg.sender == b.poster, "Only poster");
        require(b.status == Status.Submitted, "Work not submitted");

        b.status = Status.Completed;
        b.token.safeTransfer(b.worker, b.reward);
        emit BountyCompleted(id, b.worker, b.reward);
    }

    /**
     * @notice Poster reclaims reward if deadline passed without completion.
     */
    function expireBounty(uint256 id) external {
        Bounty storage b = bounties[id];
        require(msg.sender == b.poster, "Only poster");
        require(block.timestamp >= b.deadline, "Not expired yet");
        require(b.status == Status.Open || b.status == Status.Claimed, "Cannot expire");

        b.status = Status.Expired;
        b.token.safeTransfer(b.poster, b.reward);
        emit BountyExpired(id);
    }

    /**
     * @notice Get bounty details (for agents to browse available work).
     */
    function getBounty(uint256 id) external view returns (
        address poster,
        uint256 reward,
        string memory description,
        uint256 deadline,
        Status status
    ) {
        Bounty storage b = bounties[id];
        return (b.poster, b.reward, b.description, b.deadline, b.status);
    }
}
