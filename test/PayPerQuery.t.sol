// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PayPerQuery.sol";
import "./MockSBC.sol";

contract PayPerQueryTest is Test {
    PayPerQuery ppq;
    MockSBC token;
    address provider = address(this);
    address consumer = address(0xBEEF);

    uint256 constant PRICE = 100_000; // 0.1 SBC per query

    function setUp() public {
        token = new MockSBC();
        ppq = new PayPerQuery(IERC20(address(token)), PRICE);

        // Fund consumer
        token.transfer(consumer, 10 * 10 ** 6);
        vm.prank(consumer);
        token.approve(address(ppq), type(uint256).max);
    }

    function test_depositAndQuery() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6); // 1 SBC

        assertEq(ppq.balances(consumer), 1 * 10 ** 6);

        // Make 3 queries
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(consumer);
            ppq.query(keccak256(abi.encodePacked("query-", i)));
        }

        assertEq(ppq.totalQueries(), 3);
        assertEq(ppq.balances(consumer), 1 * 10 ** 6 - 3 * PRICE);
        assertEq(ppq.providerRevenue(), 3 * PRICE);
    }

    function test_collectRevenue() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        vm.prank(consumer);
        ppq.query(keccak256("q1"));

        uint256 balBefore = token.balanceOf(provider);
        ppq.collectRevenue();
        assertEq(token.balanceOf(provider), balBefore + PRICE);
    }

    function test_withdrawUnused() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        vm.prank(consumer);
        ppq.query(keccak256("q1"));

        uint256 remaining = 1 * 10 ** 6 - PRICE;
        vm.prank(consumer);
        ppq.withdraw(remaining);

        assertEq(ppq.balances(consumer), 0);
    }

    function test_insufficientBalance() public {
        vm.prank(consumer);
        ppq.deposit(PRICE - 1); // Not enough for one query

        vm.prank(consumer);
        vm.expectRevert("Insufficient balance");
        ppq.query(keccak256("q1"));
    }

    function test_updatePrice() public {
        ppq.setPrice(200_000);
        assertEq(ppq.pricePerQuery(), 200_000);
    }

    // --- Edge case tests ---

    function test_zeroPriceQuerySucceeds() public {
        ppq.setPrice(0);

        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        // Query with zero price should work and not deduct anything
        vm.prank(consumer);
        ppq.query(keccak256("free-query"));

        assertEq(ppq.balances(consumer), 1 * 10 ** 6);
        assertEq(ppq.providerRevenue(), 0);
        assertEq(ppq.totalQueries(), 1);
    }

    function test_zeroPriceQueryWithZeroBalanceSucceeds() public {
        ppq.setPrice(0);

        // Don't deposit anything — zero balance should still work with zero price
        vm.prank(consumer);
        ppq.query(keccak256("free-query"));

        assertEq(ppq.totalQueries(), 1);
    }

    function test_doubleCollectRevenueFails() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        vm.prank(consumer);
        ppq.query(keccak256("q1"));

        // First collect works
        ppq.collectRevenue();
        assertEq(ppq.providerRevenue(), 0);

        // Second collect should fail
        vm.expectRevert("No revenue to collect");
        ppq.collectRevenue();
    }

    function test_collectRevenueNonProviderFails() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        vm.prank(consumer);
        ppq.query(keccak256("q1"));

        vm.prank(consumer);
        vm.expectRevert("Only provider");
        ppq.collectRevenue();
    }

    function test_setPriceNonProviderFails() public {
        vm.prank(consumer);
        vm.expectRevert("Only provider");
        ppq.setPrice(999);
    }

    function test_withdrawMoreThanBalanceFails() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        vm.prank(consumer);
        vm.expectRevert("Insufficient balance");
        ppq.withdraw(2 * 10 ** 6);
    }

    function test_withdrawZeroSucceeds() public {
        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        // Withdrawing zero should succeed (no-op)
        vm.prank(consumer);
        ppq.withdraw(0);

        assertEq(ppq.balances(consumer), 1 * 10 ** 6);
    }

    function test_queryAfterPriceIncrease() public {
        vm.prank(consumer);
        ppq.deposit(PRICE * 2); // Enough for 2 queries at original price

        vm.prank(consumer);
        ppq.query(keccak256("q1")); // Uses original price

        // Provider doubles the price
        ppq.setPrice(PRICE * 2);

        // Consumer can now only afford 0 more queries (balance = PRICE, new price = PRICE*2)
        vm.prank(consumer);
        vm.expectRevert("Insufficient balance");
        ppq.query(keccak256("q2"));
    }

    function test_multipleConsumers() public {
        address consumer2 = address(0xCAFE);
        token.transfer(consumer2, 10 * 10 ** 6);
        vm.prank(consumer2);
        token.approve(address(ppq), type(uint256).max);

        vm.prank(consumer);
        ppq.deposit(1 * 10 ** 6);

        vm.prank(consumer2);
        ppq.deposit(2 * 10 ** 6);

        vm.prank(consumer);
        ppq.query(keccak256("q1"));

        vm.prank(consumer2);
        ppq.query(keccak256("q2"));

        assertEq(ppq.balances(consumer), 1 * 10 ** 6 - PRICE);
        assertEq(ppq.balances(consumer2), 2 * 10 ** 6 - PRICE);
        assertEq(ppq.providerRevenue(), PRICE * 2);
        assertEq(ppq.totalQueries(), 2);
    }
}
