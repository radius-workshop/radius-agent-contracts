// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BountyBoard.sol";
import "./MockSBC.sol";

contract BountyBoardTest is Test {
    BountyBoard board;
    MockSBC token;
    address poster = address(0xBEEF);
    address worker = address(0xCAFE);

    function setUp() public {
        token = new MockSBC();
        board = new BountyBoard();

        token.transfer(poster, 100 * 10 ** 6);
        vm.prank(poster);
        token.approve(address(board), type(uint256).max);
    }

    function test_fullBountyFlow() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Write a report", block.timestamp + 1 days
        );

        vm.prank(worker);
        board.claimBounty(id);

        vm.prank(worker);
        board.submitWork(id, keccak256("report"));

        vm.prank(poster);
        board.approveBounty(id);

        assertEq(token.balanceOf(worker), 5 * 10 ** 6);
    }

    function test_expireBounty() public {
        uint256 balBefore = token.balanceOf(poster);

        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Research task", block.timestamp + 1 hours
        );

        vm.warp(block.timestamp + 2 hours);

        vm.prank(poster);
        board.expireBounty(id);

        assertEq(token.balanceOf(poster), balBefore);
    }

    function test_getBountyDetails() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 3 * 10 ** 6, "Data analysis", block.timestamp + 1 days
        );

        (address p, uint256 reward, string memory desc, , BountyBoard.Status status) = board.getBounty(id);
        assertEq(p, poster);
        assertEq(reward, 3 * 10 ** 6);
        assertEq(desc, "Data analysis");
        assertEq(uint(status), uint(BountyBoard.Status.Open));
    }

    // --- Edge case tests ---

    function test_claimExpiredBountyFails() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 hours
        );

        vm.warp(block.timestamp + 2 hours);

        vm.prank(worker);
        vm.expectRevert("Expired");
        board.claimBounty(id);
    }

    function test_nonWorkerSubmitFails() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 days
        );

        vm.prank(worker);
        board.claimBounty(id);

        address stranger = address(0xDEAD);
        vm.prank(stranger);
        vm.expectRevert("Only assigned worker");
        board.submitWork(id, keccak256("result"));
    }

    function test_nonPosterCannotApprove() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 days
        );

        vm.prank(worker);
        board.claimBounty(id);

        vm.prank(worker);
        board.submitWork(id, keccak256("result"));

        vm.prank(worker);
        vm.expectRevert("Only poster");
        board.approveBounty(id);
    }

    function test_nonPosterCannotExpire() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 hours
        );

        vm.warp(block.timestamp + 2 hours);

        vm.prank(worker);
        vm.expectRevert("Only poster");
        board.expireBounty(id);
    }

    function test_cannotExpireBeforeDeadline() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 hours
        );

        vm.prank(poster);
        vm.expectRevert("Not expired yet");
        board.expireBounty(id);
    }

    function test_cannotExpireSubmittedBounty() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 days
        );

        vm.prank(worker);
        board.claimBounty(id);

        vm.prank(worker);
        board.submitWork(id, keccak256("result"));

        vm.warp(block.timestamp + 2 days);

        vm.prank(poster);
        vm.expectRevert("Cannot expire");
        board.expireBounty(id);
    }

    function test_cannotExpireCompletedBounty() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 days
        );

        vm.prank(worker);
        board.claimBounty(id);

        vm.prank(worker);
        board.submitWork(id, keccak256("result"));

        vm.prank(poster);
        board.approveBounty(id);

        vm.warp(block.timestamp + 2 days);

        vm.prank(poster);
        vm.expectRevert("Cannot expire");
        board.expireBounty(id);
    }

    function test_doubleClaimFails() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 days
        );

        vm.prank(worker);
        board.claimBounty(id);

        address worker2 = address(0xBAAD);
        vm.prank(worker2);
        vm.expectRevert("Not open");
        board.claimBounty(id);
    }

    function test_submitWithoutClaimFails() public {
        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 days
        );

        vm.prank(worker);
        vm.expectRevert("Only assigned worker");
        board.submitWork(id, keccak256("result"));
    }

    function test_zeroRewardFails() public {
        vm.prank(poster);
        vm.expectRevert("Reward must be > 0");
        board.postBounty(
            IERC20(address(token)), 0, "Task", block.timestamp + 1 days
        );
    }

    function test_pastDeadlineFails() public {
        vm.prank(poster);
        vm.expectRevert("Deadline must be in the future");
        board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp - 1
        );
    }

    function test_expireClaimedButNotSubmittedBounty() public {
        uint256 balBefore = token.balanceOf(poster);

        vm.prank(poster);
        uint256 id = board.postBounty(
            IERC20(address(token)), 5 * 10 ** 6, "Task", block.timestamp + 1 hours
        );

        vm.prank(worker);
        board.claimBounty(id);

        vm.warp(block.timestamp + 2 hours);

        // Poster can expire a claimed-but-not-submitted bounty
        vm.prank(poster);
        board.expireBounty(id);

        assertEq(token.balanceOf(poster), balBefore);
    }
}
