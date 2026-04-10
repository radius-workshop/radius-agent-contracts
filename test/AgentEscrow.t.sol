// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentEscrow.sol";
import "./MockSBC.sol";

contract AgentEscrowTest is Test {
    AgentEscrow escrow;
    MockSBC token;
    address buyer = address(0xBEEF);
    address provider = address(0xCAFE);

    function setUp() public {
        token = new MockSBC();
        escrow = new AgentEscrow();

        // Fund buyer
        token.transfer(buyer, 100 * 10 ** 6);
        vm.prank(buyer);
        token.approve(address(escrow), type(uint256).max);
    }

    function test_createAndApprove() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        // Provider completes
        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        // Buyer approves
        vm.prank(buyer);
        escrow.approve(id);

        assertEq(token.balanceOf(provider), 10 * 10 ** 6);
    }

    function test_refundAfterDeadline() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        uint256 balBefore = token.balanceOf(buyer);

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        vm.prank(buyer);
        escrow.refund(id);

        assertEq(token.balanceOf(buyer), balBefore + 10 * 10 ** 6);
    }

    function test_forceReleaseAfterDeadline() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        // Warp past deadline, buyer hasn't responded
        vm.warp(block.timestamp + 2 hours);

        vm.prank(provider);
        escrow.forceRelease(id);

        assertEq(token.balanceOf(provider), 10 * 10 ** 6);
    }

    function test_dispute() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(buyer);
        escrow.dispute(id);

        (, , , , , , , AgentEscrow.Status status) = escrow.escrows(id);
        assertEq(uint(status), uint(AgentEscrow.Status.Disputed));
    }

    // --- Access control edge cases ---

    function test_nonPartyCannotComplete() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert("Only provider");
        escrow.complete(id, keccak256("result"));
    }

    function test_nonPartyCannotApprove() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert("Only buyer");
        escrow.approve(id);
    }

    function test_nonPartyCannotDispute() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert("Not a party");
        escrow.dispute(id);
    }

    function test_nonPartyCannotRefund() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.warp(block.timestamp + 2 hours);

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert("Only buyer");
        escrow.refund(id);
    }

    function test_nonPartyCannotForceRelease() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        vm.warp(block.timestamp + 2 hours);

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert("Only provider");
        escrow.forceRelease(id);
    }

    // --- State transition edge cases ---

    function test_forceReleaseBeforeDeadlineFails() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        // Try to force-release immediately (before deadline)
        vm.prank(provider);
        vm.expectRevert("Deadline not reached");
        escrow.forceRelease(id);
    }

    function test_doubleApproveFails() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        vm.prank(buyer);
        escrow.approve(id);

        // Second approve should fail
        vm.prank(buyer);
        vm.expectRevert("Not completed");
        escrow.approve(id);
    }

    function test_doubleDisputeFails() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(buyer);
        escrow.dispute(id);

        // Second dispute should fail since status is Disputed (not Active or Completed)
        vm.prank(provider);
        vm.expectRevert("Cannot dispute");
        escrow.dispute(id);
    }

    function test_refundBeforeDeadlineFails() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(buyer);
        vm.expectRevert("Deadline not reached");
        escrow.refund(id);
    }

    function test_cannotCompleteAfterDispute() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(buyer);
        escrow.dispute(id);

        vm.prank(provider);
        vm.expectRevert("Not active");
        escrow.complete(id, keccak256("result"));
    }

    function test_cannotRefundAfterCompletion() public {
        vm.prank(buyer);
        uint256 id = escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );

        vm.prank(provider);
        escrow.complete(id, keccak256("result"));

        vm.warp(block.timestamp + 2 hours);

        vm.prank(buyer);
        vm.expectRevert("Not active");
        escrow.refund(id);
    }

    function test_createEscrowInvalidProvider() public {
        vm.prank(buyer);
        vm.expectRevert("Invalid provider");
        escrow.createEscrow(
            address(0), IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 1 hours
        );
    }

    function test_createEscrowZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert("Amount must be > 0");
        escrow.createEscrow(
            provider, IERC20(address(token)), 0, keccak256("task"), 1 hours
        );
    }

    function test_createEscrowZeroTimeout() public {
        vm.prank(buyer);
        vm.expectRevert("Timeout must be > 0");
        escrow.createEscrow(
            provider, IERC20(address(token)), 10 * 10 ** 6, keccak256("task"), 0
        );
    }

}
