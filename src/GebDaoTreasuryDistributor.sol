// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.7;

import "./lib/GebAuth.sol";
import "./lib/LinkedList.sol";
import "./lib/GebMath.sol";

abstract contract GebDaoMinimalTreasuryLike {
    function epochLength() external virtual view returns (uint256);
    function delegateAllowance() external virtual view returns (uint256);
    function delegateLeftoverToSpend() external virtual view returns (uint256);
    function epochStart() external virtual view returns (uint256);
    function delegateTransferERC20(address, uint256) external virtual;
}

abstract contract TokenLike {
    function transfer(address, uint256) external virtual;
}

/**
* @notice   Treasury distributor
*           Should be setup as the delegate in the GebDaoMinimalTreasury contract
*           (https://github.com/reflexer-labs/geb-dao-minimal-treasury)
*           Distribute the delegate budget to up to 5 targets, according to preset weights
**/
contract GebDaoTreasuryDistributor is GebAuth, GebMath {
    using LinkedList for LinkedList.List;

    // --- State vars ---
    // maximum amount of targets (constant)
    uint256 public constant maxTargets = 5;
    // GebDaoMinimalTreasury
    GebDaoMinimalTreasuryLike public treasury;
    // Total distribution weight
    uint256 public totalWeight;
    // Mapping of target weights used for distribution
    mapping (address => uint256) public targetWeights;
    // List of targets
    LinkedList.List internal targetList;
    // Last target on the list
    address public lastTarget;

    // --- Events ---
    event TargetAdded(address target, uint256 weight, uint256 totalWeight);
    event TargetModified(address target, uint256 weight, uint256 totalWeight);
    event TargetRemoved(address target, uint256 totalWeight);

    // --- Constructor ---
    /**
     * @notice Constructor
     * @param treasuryAddress Address of the minimal treasury
     * @param targets Targets
     * @param weights Weights
     */
    constructor(
        address          treasuryAddress,
        address[] memory targets,
        uint256[] memory weights
    ) public {
        require(treasuryAddress != address(0), "GebDaoTreasuryDistributor/null-treasury");
        require(targets.length == weights.length, "GebDaoTreasuryDistributor/invalid-data");

        treasury = GebDaoMinimalTreasuryLike(treasuryAddress);

        for (uint256 i; i < targets.length; i++)
            addTarget(targets[i], weights[i]);
    }

    // --- Admin functions ---
    /**
     * @notice Adds a target
     * @param target Address of the distribution target
     * @param weight Weight, determines the amount distributed to the target
     */
    function addTarget(address target, uint256 weight) public isAuthorized {
        require(target != address(0), "GebDaoTreasuryDistributor/null-account");
        require(weight > 0, "GebDaoTreasuryDistributor/invalid-weight");
        require(targetList.range() < maxTargets, "GebDaoTreasuryDistributor/too-many-targets");
        require(targetWeights[target] == 0, "GebDaoTreasuryDistributor/target-already-exists");

        totalWeight = addition(totalWeight, weight);
        targetWeights[target] = weight;
        require(targetList.push(uint256(target), false), "GebDaoTreasuryDistributor/failed-adding-target");
        lastTarget = target;

        emit TargetAdded(target, weight, totalWeight);
    }

    /**
     * @notice Modifies a target weight
     * @param target Address of the distribution target
     * @param weight Weight, determines the amount distributed to the target
     */
    function modifyTarget(address target, uint256 weight) external isAuthorized {
        require(weight > 0, "GebDaoTreasuryDistributor/invalid-weight");
        require(targetWeights[target] != 0, "GebDaoTreasuryDistributor/target-does-not-exist");

        totalWeight = addition(subtract(totalWeight, targetWeights[target]), weight);
        targetWeights[target] = weight;

        emit TargetModified(target, weight, totalWeight);
    }

    /**
     * @notice Removes a target
     * @param target Address of the distribution target
     */
    function removeTarget(address target) external isAuthorized {
        require(targetWeights[target] != 0, "GebDaoTreasuryDistributor/target-does-not-exist");

        totalWeight = subtract(totalWeight, targetWeights[target]);
        delete targetWeights[target];

        if (lastTarget == target) {
            (, uint prevTarget) = targetList.prev(uint256(target));
            lastTarget = address(prevTarget);
        }

        require(targetList.del(uint256(target)) != 0, "GebDaoTreasuryDistributor/failed-removing-target");

        emit TargetRemoved(target, totalWeight);
    }

    /**
     * @notice Transfer any token from treasury to dst (admin only)
     * @param token The address of the token to be transferred
     * @param dst The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function transferERC20(address token, address dst, uint256 amount) external isAuthorized {
        TokenLike(token).transfer(dst, amount);
    }

    // --- Distribution logic ---
    /**
     * @notice Distributes funds available on the treasury according to preset weights
     */
    function distributeFunds() external {
        uint totalAmount = treasury.delegateLeftoverToSpend();
        require(totalAmount > 0, "GebDaoTreasuryDistributor/no-balance");
        uint currentTarget = uint256(lastTarget);

        while (currentTarget > 0) {
            treasury.delegateTransferERC20(address(currentTarget), multiply(totalAmount, targetWeights[address(currentTarget)]) / totalWeight);
            (, currentTarget) = targetList.prev(currentTarget);
        }
    }
}
