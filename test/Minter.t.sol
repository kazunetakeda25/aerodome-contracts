// 1:1 with Hardhat test
pragma solidity 0.8.13;

import "./BaseTest.sol";

contract MinterTest is BaseTest {
    using stdStorage for StdStorage;
    uint256 tokenId;

    event Nudge(uint256 indexed _period, uint256 _oldRate, uint256 _newRate);

    function _setUp() public override {
        VELO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pair);
        pools[1] = address(pair2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        skip(1 hours);
        voter.vote(tokenId, pools, weights);
    }

    function testMinterDeploy() public {
        assertEq(minter.MAXIMUM_TAIL_RATE(), 100); // 1%
        assertEq(minter.MINIMUM_TAIL_RATE(), 1); // .01%
        assertEq(minter.WEEKLY_DECAY(), 9_900);
        assertEq(minter.TAIL_START(), 6_000_000 * 1e18);
        assertEq(minter.weekly(), 15_000_000 * 1e18);
        assertEq(minter.tailEmissionRate(), 30); // .3%
        assertEq(minter.active_period(), 604800);
    }

    function testTailEmissionFlipsWhenWeeklyEmissionDecaysBelowTailStart() public {
        skipToNextEpoch(1);

        assertEq(VELO.balanceOf(address(voter)), 0);

        // 6_010_270 * 1e18 ~= approximate weekly value after 91 epochs
        // (last epoch prior to tail emissions kicking in)
        stdstore.target(address(minter)).sig("weekly()").checked_write(6_010_270 * 1e18);

        skipToNextEpoch(1);
        minter.update_period();
        assertApproxEqRel(VELO.balanceOf(address(voter)), 6_010_270 * 1e18, 1e12);
        voter.distribute(0, voter.length());

        skipToNextEpoch(1);
        // totalSupply ~= 56_010_270 * 1e18
        // expected mint = totalSupply * .3% ~= 168_030
        minter.update_period();
        assertApproxEqAbs(VELO.balanceOf(address(voter)), 168_030 * 1e18, TOKEN_1);
        assertLt(minter.weekly(), 6_000_000 * 1e18);
    }

    function testCannotNudgeIfNotInTailEmissionsYet() public {
        vm.prank(address(epochGovernor));
        vm.expectRevert(IMinter.TailEmissionsInactive.selector);
        minter.nudge();
    }

    function testCannotNudgeIfNotEpochGovernor() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("weekly()").checked_write(5_999_999 * 1e18);

        vm.prank(address(owner2));
        vm.expectRevert(IMinter.NotEpochGovernor.selector);
        minter.nudge();
    }

    function testCannotNudgeIfAlreadyNudged() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("weekly()").checked_write(5_999_999 * 1e18);
        assertFalse(minter.proposals(604800));

        vm.prank(address(epochGovernor));
        minter.nudge();
        assertTrue(minter.proposals(604800));
        skip(1);

        vm.expectRevert(IMinter.AlreadyNudged.selector);
        vm.prank(address(epochGovernor));
        minter.nudge();
    }

    function testNudgeWhenAtUpperBoundary() public {
        stdstore.target(address(minter)).sig("weekly()").checked_write(5_999_999 * 1e18);
        stdstore.target(address(minter)).sig("tailEmissionRate()").checked_write(100);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4); // nudge up
        assertEq(minter.tailEmissionRate(), 100);

        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 100); // nudge above at maximum does nothing

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3); // nudge down

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 100, 99);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 99);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6); // no nudge

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 99, 99);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 99);
        assertTrue(minter.proposals(1814400));
    }

    function testNudgeWhenAtLowerBoundary() public {
        stdstore.target(address(minter)).sig("weekly()").checked_write(5_999_999 * 1e18);
        stdstore.target(address(minter)).sig("tailEmissionRate()").checked_write(1);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3); // nudge down
        assertEq(minter.tailEmissionRate(), 1);

        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 1); // nudge below at minimum does nothing

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4); // nudge up

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 1, 2);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 2);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6); // no nudge

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 2, 2);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 2);
        assertTrue(minter.proposals(1814400));
    }

    function testNudge() public {
        stdstore.target(address(minter)).sig("weekly()").checked_write(5_999_999 * 1e18);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4); // nudge up
        assertEq(minter.tailEmissionRate(), 30);

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(604800, 30, 31);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 31);
        assertTrue(minter.proposals(604800));

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3); // nudge down

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 31, 30);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 30);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.update_period();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6); // no nudge

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 30, 30);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 30);
        assertTrue(minter.proposals(1814400));
    }

    function testMinterWeeklyDistribute() public {
        minter.update_period();
        assertEq(minter.weekly(), 15 * TOKEN_1M); // 15M

        uint256 pre = VELO.balanceOf(address(voter));
        skipToNextEpoch(1);
        minter.update_period();
        assertEq(distributor.claimable(tokenId), 0);
        // emissions decay by 1% after one epoch
        uint256 post = VELO.balanceOf(address(voter));
        assertEq(post - pre, (15 * TOKEN_1M));
        assertEq(minter.weekly(), ((15 * TOKEN_1M) * 99) / 100);

        pre = post;
        skipToNextEpoch(1);
        vm.roll(block.number + 1);
        minter.update_period();
        post = VELO.balanceOf(address(voter));

        // check rebase accumulated
        assertGt(distributor.claimable(1), 0);
        distributor.claim(1);
        assertEq(distributor.claimable(1), 0);

        assertEq(post - pre, (15 * TOKEN_1M * 99) / 100);
        assertEq(minter.weekly(), (((15 * TOKEN_1M * 99) / 100) * 99) / 100);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();

        distributor.claim(1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        distributor.claimMany(tokenIds);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        distributor.claim(1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        distributor.claimMany(tokenIds);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.update_period();
        distributor.claim(1);
    }
}
