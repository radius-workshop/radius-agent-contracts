// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PaymentSplitter
 * @notice Revenue sharing for agent swarms. When agents collaborate on a task,
 *         payments can be split automatically among team members.
 *
 * Flow:
 *   1. Deploy with a list of payee addresses and their share weights
 *   2. Anyone sends SBC to the contract via depositSBC()
 *   3. Each payee calls claimShare() to withdraw their proportional cut
 *
 * Example: Three agents collaborate. Agent A (orchestrator) gets 50%,
 * Agent B (researcher) gets 30%, Agent C (writer) gets 20%.
 * Deploy with shares [50, 30, 20].
 */
contract PaymentSplitter {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public totalShares;
    uint256 public totalDeposited;
    uint256 public totalClaimed;

    address[] public payees;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public claimed;

    event Deposited(address indexed from, uint256 amount);
    event Claimed(address indexed payee, uint256 amount);

    /**
     * @param _token The ERC-20 token to split (e.g. SBC)
     * @param _payees Array of payee addresses
     * @param _shares Array of share weights (must match payees length)
     */
    constructor(IERC20 _token, address[] memory _payees, uint256[] memory _shares) {
        require(_payees.length == _shares.length, "Length mismatch");
        require(_payees.length > 0, "No payees");

        token = _token;
        for (uint256 i = 0; i < _payees.length; i++) {
            require(_payees[i] != address(0), "Zero address");
            require(_shares[i] > 0, "Zero share");
            require(shares[_payees[i]] == 0, "Duplicate payee");

            payees.push(_payees[i]);
            shares[_payees[i]] = _shares[i];
            totalShares += _shares[i];
        }
    }

    /**
     * @notice Deposit SBC into the splitter. Must approve this contract first.
     */
    function depositSBC(uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Claim your proportional share of all deposits.
     */
    function claimShare() external {
        uint256 share = shares[msg.sender];
        require(share > 0, "Not a payee");

        uint256 totalOwed = (totalDeposited * share) / totalShares;
        uint256 claimable = totalOwed - claimed[msg.sender];
        require(claimable > 0, "Nothing to claim");

        claimed[msg.sender] += claimable;
        totalClaimed += claimable;
        token.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable);
    }

    /**
     * @notice Check how much a payee can currently claim.
     */
    function pendingShare(address payee) external view returns (uint256) {
        uint256 share = shares[payee];
        if (share == 0) return 0;
        uint256 totalOwed = (totalDeposited * share) / totalShares;
        return totalOwed - claimed[payee];
    }

    /**
     * @notice Get the number of payees.
     */
    function payeeCount() external view returns (uint256) {
        return payees.length;
    }
}
