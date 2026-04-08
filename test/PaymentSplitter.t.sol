// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PaymentSplitter.sol";
import "./MockSBC.sol";

contract PaymentSplitterTest is Test {
    PaymentSplitter splitter;
    MockSBC token;

    address agentA = address(0xA);
    address agentB = address(0xB);
    address agentC = address(0xC);
    address depositor = address(0xDEAD);

    function setUp() public {
        token = new MockSBC();

        address[] memory payees = new address[](3);
        payees[0] = agentA;
        payees[1] = agentB;
        payees[2] = agentC;

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50; // 50%
        shares[1] = 30; // 30%
        shares[2] = 20; // 20%

        splitter = new PaymentSplitter(IERC20(address(token)), payees, shares);

        // Fund depositor
        token.transfer(depositor, 100 * 10 ** 6);
        vm.prank(depositor);
        token.approve(address(splitter), type(uint256).max);
    }

    function test_splitPayment() public {
        vm.prank(depositor);
        splitter.depositSBC(10 * 10 ** 6); // 10 SBC

        // Agent A claims 50% = 5 SBC
        vm.prank(agentA);
        splitter.claimShare();
        assertEq(token.balanceOf(agentA), 5 * 10 ** 6);

        // Agent B claims 30% = 3 SBC
        vm.prank(agentB);
        splitter.claimShare();
        assertEq(token.balanceOf(agentB), 3 * 10 ** 6);

        // Agent C claims 20% = 2 SBC
        vm.prank(agentC);
        splitter.claimShare();
        assertEq(token.balanceOf(agentC), 2 * 10 ** 6);
    }

    function test_pendingShare() public {
        vm.prank(depositor);
        splitter.depositSBC(10 * 10 ** 6);

        assertEq(splitter.pendingShare(agentA), 5 * 10 ** 6);
        assertEq(splitter.pendingShare(agentB), 3 * 10 ** 6);
        assertEq(splitter.pendingShare(agentC), 2 * 10 ** 6);
    }

    function test_multipleDeposits() public {
        vm.prank(depositor);
        splitter.depositSBC(10 * 10 ** 6);

        // Agent A claims first deposit share
        vm.prank(agentA);
        splitter.claimShare();
        assertEq(token.balanceOf(agentA), 5 * 10 ** 6);

        // Second deposit
        vm.prank(depositor);
        splitter.depositSBC(20 * 10 ** 6);

        // Agent A claims the new portion (50% of 20 = 10)
        vm.prank(agentA);
        splitter.claimShare();
        assertEq(token.balanceOf(agentA), 15 * 10 ** 6);
    }

    function test_nonPayeeCannotClaim() public {
        vm.prank(depositor);
        splitter.depositSBC(10 * 10 ** 6);

        vm.prank(depositor);
        vm.expectRevert("Not a payee");
        splitter.claimShare();
    }

    // --- Edge case tests ---

    function test_claimWithZeroPendingFails() public {
        // No deposit — nothing to claim
        vm.prank(agentA);
        vm.expectRevert("Nothing to claim");
        splitter.claimShare();
    }

    function test_doubleClaimSameDeposit() public {
        vm.prank(depositor);
        splitter.depositSBC(10 * 10 ** 6);

        vm.prank(agentA);
        splitter.claimShare();
        assertEq(token.balanceOf(agentA), 5 * 10 ** 6);

        // Second claim with no new deposit should fail
        vm.prank(agentA);
        vm.expectRevert("Nothing to claim");
        splitter.claimShare();
    }

    function test_roundingBehaviorSmallDeposit() public {
        // Deposit 1 unit with shares [50, 30, 20] and totalShares=100
        vm.prank(depositor);
        splitter.depositSBC(1);

        // 1 * 50 / 100 = 0, 1 * 30 / 100 = 0, 1 * 20 / 100 = 0
        // All truncate to 0, so no one can claim
        assertEq(splitter.pendingShare(agentA), 0);
        assertEq(splitter.pendingShare(agentB), 0);
        assertEq(splitter.pendingShare(agentC), 0);
    }

    function test_roundingDustStuck() public {
        // Deposit an amount that doesn't divide evenly
        // 10000001 with shares [50, 30, 20], totalShares=100
        // A: 10000001 * 50 / 100 = 5000000
        // B: 10000001 * 30 / 100 = 3000000
        // C: 10000001 * 20 / 100 = 2000000
        // Total claimable: 10000000, dust: 1
        vm.prank(depositor);
        splitter.depositSBC(10_000_001);

        assertEq(splitter.pendingShare(agentA), 5_000_000);
        assertEq(splitter.pendingShare(agentB), 3_000_000);
        assertEq(splitter.pendingShare(agentC), 2_000_000);

        // Claim all
        vm.prank(agentA);
        splitter.claimShare();
        vm.prank(agentB);
        splitter.claimShare();
        vm.prank(agentC);
        splitter.claimShare();

        // 1 unit of dust is stuck in the contract
        uint256 contractBalance = token.balanceOf(address(splitter));
        assertEq(contractBalance, 1);
    }

    function test_pendingShareNonPayee() public {
        vm.prank(depositor);
        splitter.depositSBC(10 * 10 ** 6);

        // Non-payee should get 0
        assertEq(splitter.pendingShare(depositor), 0);
    }

    function test_payeeCount() public {
        assertEq(splitter.payeeCount(), 3);
    }

    function test_constructorZeroPayeesFails() public {
        address[] memory emptyPayees = new address[](0);
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert("No payees");
        new PaymentSplitter(IERC20(address(token)), emptyPayees, emptyShares);
    }

    function test_constructorLengthMismatchFails() public {
        address[] memory payees = new address[](2);
        payees[0] = address(0x1);
        payees[1] = address(0x2);

        uint256[] memory badShares = new uint256[](1);
        badShares[0] = 50;

        vm.expectRevert("Length mismatch");
        new PaymentSplitter(IERC20(address(token)), payees, badShares);
    }

    function test_constructorZeroAddressFails() public {
        address[] memory payees = new address[](1);
        payees[0] = address(0);

        uint256[] memory s = new uint256[](1);
        s[0] = 50;

        vm.expectRevert("Zero address");
        new PaymentSplitter(IERC20(address(token)), payees, s);
    }

    function test_constructorZeroShareFails() public {
        address[] memory payees = new address[](1);
        payees[0] = address(0x1);

        uint256[] memory s = new uint256[](1);
        s[0] = 0;

        vm.expectRevert("Zero share");
        new PaymentSplitter(IERC20(address(token)), payees, s);
    }

    function test_constructorDuplicatePayeeFails() public {
        address[] memory payees = new address[](2);
        payees[0] = address(0x1);
        payees[1] = address(0x1);

        uint256[] memory s = new uint256[](2);
        s[0] = 50;
        s[1] = 50;

        vm.expectRevert("Duplicate payee");
        new PaymentSplitter(IERC20(address(token)), payees, s);
    }

    function test_twoPayeesUnequalShares() public {
        address[] memory payees = new address[](2);
        payees[0] = address(0x1);
        payees[1] = address(0x2);

        uint256[] memory s = new uint256[](2);
        s[0] = 1;
        s[1] = 2;

        PaymentSplitter splitter2 = new PaymentSplitter(IERC20(address(token)), payees, s);

        token.transfer(depositor, 100 * 10 ** 6);
        vm.prank(depositor);
        token.approve(address(splitter2), type(uint256).max);

        vm.prank(depositor);
        splitter2.depositSBC(3 * 10 ** 6);

        // 1/3 share and 2/3 share
        assertEq(splitter2.pendingShare(address(0x1)), 1 * 10 ** 6);
        assertEq(splitter2.pendingShare(address(0x2)), 2 * 10 ** 6);
    }
}
