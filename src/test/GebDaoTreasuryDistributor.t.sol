// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import {GebDaoMinimalTreasury} from "geb-dao-minimal-treasury/GebDaoMinimalTreasury.sol";

import "../GebDaoTreasuryDistributor.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
    function prank(address) virtual public;
}

contract GebDaoTreasuryDistributorTest is DSTest {
    Hevm hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DSToken token;
    GebDaoMinimalTreasury treasury;
    GebDaoTreasuryDistributor distributor;

    // treasury params
    uint256 constant epochLength = 4 weeks;
    uint256 constant allowance   = 100 ether;
    uint256 constant initialTreasuryBalance = 1e6 ether;

    // distributor params
    address[] targets = [
        address(1001),
        address(1002),
        address(1003),
        address(1004)
    ];
    uint[] weights = [
        10,
        20,
        30,
        40
    ];

    function setUp() public {
        token = new DSToken("name", "symbol");

        treasury = new GebDaoMinimalTreasury(
            address(token),
            address(0),
            epochLength,
            allowance
        );

        distributor = new GebDaoTreasuryDistributor(
            address(treasury),
            targets,
            weights
        );

        treasury.modifyParameters("treasuryDelegate", address(distributor));

        token.mint(address(treasury), initialTreasuryBalance);
    }

    function test_setup() public {
        assertEq(address(distributor.treasury()), address(treasury));
        assertEq(distributor.totalWeight(), 100);
        assertEq(distributor.lastTarget(), targets[3]);

        for (uint i; i < 4; i++)
            assertEq(distributor.targetWeights(targets[i]), weights[i]);
    }

    function testFail_setup_null_treasury() public {
        distributor = new GebDaoTreasuryDistributor(
            address(0),
            targets,
            weights
        );
    }

    function testFail_setup_invalid_data(address[] memory targets_, uint[] memory weights_) public {
        if (targets_.length == weights_.length) revert();
        distributor = new GebDaoTreasuryDistributor(
            address(treasury),
            targets_,
            weights_
        );
    }

    function test_add_target() public {
        address newTarget = address(1005);
        distributor.addTarget(newTarget, 100);

        assertEq(distributor.totalWeight(), 200);
        assertEq(distributor.lastTarget(), newTarget);
        assertEq(distributor.targetWeights(newTarget), 100);
    }

    function testFail_add_target_null_target() public {
        distributor.addTarget(address(0), 100);
    }

    function testFail_add_target_null_weight() public {
        distributor.addTarget(address(1005), 0);
    }

    function testFail_add_target_too_many() public {
        distributor.addTarget(address(1005), 100);
        distributor.addTarget(address(1006), 100);
    }

    function testFail_add_target_already_exists() public {
        distributor.addTarget(targets[0], 100);
    }

    function testFail_add_target_unauthorized() public {
        hevm.prank(address(0xfab));
        distributor.addTarget(address(1005), 100);
    }

    function test_modify_target() public {
        distributor.modifyTarget(targets[1], 120);

        assertEq(distributor.totalWeight(), 200);
        assertEq(distributor.lastTarget(), targets[3]);
        assertEq(distributor.targetWeights(targets[1]), 120);
    }

    function testFail_modify_target_null_weight() public {
        distributor.modifyTarget(targets[1], 0);
    }

    function testFail_modify_target_unexistent() public {
        distributor.modifyTarget(address(0x123), 120);
    }

    function testFail_modify_target_unauthorized() public {
        hevm.prank(address(0xfab));
        distributor.modifyTarget(targets[1], 120);
    }

    function test_remove_target() public {
        distributor.removeTarget(targets[1]);

        assertEq(distributor.totalWeight(), 80);
        assertEq(distributor.lastTarget(), targets[3]);
        assertEq(distributor.targetWeights(targets[1]), 0);
    }

    function test_remove_target_last() public {
        distributor.removeTarget(targets[3]);

        assertEq(distributor.totalWeight(), 60);
        assertEq(distributor.lastTarget(), targets[2]);
        assertEq(distributor.targetWeights(targets[3]), 0);
    }

    function testFail_remove_target_unexistent() public {
        distributor.removeTarget(address(0xdead));
    }

    function testFail_remove_target_unauthorized() public {
        hevm.prank(address(0xfab));
        distributor.removeTarget(targets[3]);
    }

    function test_transfer_ERC20() public {
        assertEq(token.balanceOf(address(distributor)), 0);

        token.mint(address(distributor), 1000 ether);
        assertEq(token.balanceOf(address(distributor)), 1000 ether);

        distributor.transferERC20(address(token), address(0xdead), 1000 ether);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(address(0xdead)), 1000 ether);
    }

    function testFail_transfer_ERC20_unauthorized() public {
        assertEq(token.balanceOf(address(distributor)), 0);

        token.mint(address(distributor), 1000 ether);
        assertEq(token.balanceOf(address(distributor)), 1000 ether);

        hevm.prank(address(0xfab));
        distributor.transferERC20(address(token), address(0xdead), 1000 ether);
    }

    function test_distribute_funds() public {
        assertEq(token.balanceOf(address(treasury)), initialTreasuryBalance);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(targets[0]), 0);
        assertEq(token.balanceOf(targets[1]), 0);
        assertEq(token.balanceOf(targets[2]), 0);
        assertEq(token.balanceOf(targets[3]), 0);

        distributor.distributeFunds();

        assertEq(token.balanceOf(address(treasury)), initialTreasuryBalance - allowance);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(targets[0]), 10 ether);
        assertEq(token.balanceOf(targets[1]), 20 ether);
        assertEq(token.balanceOf(targets[2]), 30 ether);
        assertEq(token.balanceOf(targets[3]), 40 ether);

        distributor.addTarget(address(1005), 100);
        hevm.warp(treasury.epochStart() + epochLength + 1);
        distributor.distributeFunds();

        assertEq(token.balanceOf(address(treasury)), initialTreasuryBalance - (allowance * 2));
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(targets[0]), 15 ether);
        assertEq(token.balanceOf(targets[1]), 30 ether);
        assertEq(token.balanceOf(targets[2]), 45 ether);
        assertEq(token.balanceOf(targets[3]), 60 ether);
        assertEq(token.balanceOf(address(1005)), 50 ether);

        distributor.removeTarget(address(1005));
        hevm.warp(treasury.epochStart() + epochLength + 1);
        distributor.distributeFunds();

        assertEq(token.balanceOf(address(treasury)), initialTreasuryBalance - (allowance * 3));
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(targets[0]), 25 ether);
        assertEq(token.balanceOf(targets[1]), 50 ether);
        assertEq(token.balanceOf(targets[2]), 75 ether);
        assertEq(token.balanceOf(targets[3]), 100 ether);
        assertEq(token.balanceOf(address(1005)), 50 ether);
    }

    function test_distribute_funds_gas() public {
        distributor.distributeFunds();
    }

    function test_distribute_funds_fuzz(uint _allowance, address newTarget, uint newWeight) public {
        if (newTarget == address(0)) return;                    // non null new target
        for (uint i; i < 4; i++)
            if (newTarget == targets[i]) return;                // existing target
        _allowance = (_allowance % 999999 ether) + 1 ether;     // 1 to 1M WAD
        newWeight = (newWeight % 999) + 1;                      // 1 to 1k weight
        treasury.modifyParameters("delegateAllowance", _allowance);
        hevm.warp(treasury.epochStart() + epochLength + 1);
        distributor.addTarget(newTarget, newWeight);
        distributor.distributeFunds();

        for (uint i; i < 4; i++)
            assertEq(token.balanceOf(targets[i]), weights[i] * _allowance / (100 + newWeight));

        assertEq(token.balanceOf(newTarget), newWeight * _allowance / (100 + newWeight));
        assertEq(token.balanceOf(address(distributor)), 0);
    }

    function testFail_distribute_funds_no_balance() public {
        treasury.modifyParameters("delegateAllowance", 0);
        distributor.distributeFunds();
    }
}
