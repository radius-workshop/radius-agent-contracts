// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PayPerQuery
 * @notice Metered API billing for agent services. Consumers pre-fund a balance,
 *         each query deducts a fee and emits an event. The service provider
 *         watches events and serves responses off-chain.
 *
 * This is the core micropayment pattern Radius was built for — sub-second
 * finality makes per-query billing practical and instant.
 *
 * Flow:
 *   1. Provider deploys with a price per query
 *   2. Consumer calls deposit() to pre-fund their balance
 *   3. Consumer calls query() which deducts fee and emits QueryPaid
 *   4. Provider watches QueryPaid events and serves the response off-chain
 *   5. Consumer can withdraw() unused balance at any time
 *   6. Provider calls collectRevenue() to withdraw accumulated fees
 */
contract PayPerQuery {
    using SafeERC20 for IERC20;

    address public provider;
    IERC20 public token;
    uint256 public pricePerQuery;
    uint256 public totalQueries;

    mapping(address => uint256) public balances;
    uint256 public providerRevenue;

    event Deposited(address indexed consumer, uint256 amount, uint256 newBalance);
    event QueryPaid(address indexed consumer, bytes32 queryHash, uint256 fee, uint256 queryNumber);
    event Withdrawn(address indexed consumer, uint256 amount);
    event RevenueCollected(address indexed provider, uint256 amount);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    constructor(IERC20 _token, uint256 _pricePerQuery) {
        provider = msg.sender;
        token = _token;
        pricePerQuery = _pricePerQuery;
    }

    /**
     * @notice Pre-fund your query balance. Must approve this contract first.
     */
    function deposit(uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit Deposited(msg.sender, amount, balances[msg.sender]);
    }

    /**
     * @notice Execute a paid query. Deducts fee from your balance.
     * @param queryHash Identifier for the query (e.g. hash of the request)
     */
    function query(bytes32 queryHash) external {
        require(balances[msg.sender] >= pricePerQuery, "Insufficient balance");

        balances[msg.sender] -= pricePerQuery;
        providerRevenue += pricePerQuery;
        totalQueries++;

        emit QueryPaid(msg.sender, queryHash, pricePerQuery, totalQueries);
    }

    /**
     * @notice Withdraw unused balance.
     */
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Provider collects accumulated revenue.
     */
    function collectRevenue() external {
        require(msg.sender == provider, "Only provider");
        uint256 amount = providerRevenue;
        require(amount > 0, "No revenue to collect");
        providerRevenue = 0;
        token.safeTransfer(provider, amount);
        emit RevenueCollected(provider, amount);
    }

    /**
     * @notice Provider can update the price per query.
     */
    function setPrice(uint256 newPrice) external {
        require(msg.sender == provider, "Only provider");
        emit PriceUpdated(pricePerQuery, newPrice);
        pricePerQuery = newPrice;
    }
}
