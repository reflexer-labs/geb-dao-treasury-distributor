// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./GebDaoTreasuryDistributor.sol";

contract GebDaoTreasuryDistributorTest is DSTest {
    GebDaoTreasuryDistributor distributor;

    function setUp() public {
        distributor = new GebDaoTreasuryDistributor();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
