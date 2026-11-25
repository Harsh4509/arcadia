/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { BaseVault_Fuzz_Test } from "../BaseVault/_BaseVault.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Plan } from "../../utils/Plan.sol";

/**
 * @notice Common logic needed by all "ALMVaultAsync" fuzz tests.
 */
abstract contract ALMVaultAsync_Fuzz_Test is BaseVault_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function asyncVaultFor(bool isToken0) internal view returns (ALMVaultAsync vault) {
        vault = isToken0 ? asyncVault : secondAsyncVault;
    }

    function fundRequester(bool isToken0, address owner_, uint256 assets) internal {
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        (isToken0 ? token0 : token1).mint(owner_, assets);
        vm.prank(owner_);
        (isToken0 ? token0 : token1).approve(address(asyncVaultFor(isToken0)), assets);
    }

    function requestDepositFor(bool isToken0, address owner_, uint256 assets) internal {
        fundRequester(isToken0, owner_, assets);
        vm.prank(owner_);
        asyncVaultFor(isToken0).requestDeposit(assets, owner_, owner_);
    }

    function fundRedeemer(address owner_, uint256 shares) internal {
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.mintShares(owner_, shares);
    }

    function requestRedeemFor(bool isToken0, address owner_, uint256 shares) internal {
        fundRedeemer(owner_, shares);
        vm.prank(owner_);
        asyncVaultFor(isToken0).requestRedeem(shares, owner_, owner_);
    }

    function settleDeposit(bool isToken0) internal {
        runStagingPlan(Plan.init().clearAllRequests(isToken0, true).settleRequests());
    }

    function settleRedeem(bool isToken0) internal {
        runStagingPlan(Plan.init().clearAllRequests(isToken0, false).settleRequests());
    }

    function setDepositSettled(
        PoolState memory poolState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
        address owner_
    ) internal returns (uint256 assets) {
        // And: A deposit of an aLP and up to half the pending room, requested, settled.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 value =
            amount1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        uint256 floor = (value + 1).divUp(almCore.totalSupply());
        if (isToken0) floor = floor.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
        // And: Where an aLP outgrows an amount, a hole no bound expresses.
        vm.assume(floor <= Constants.MAX_FUZZED_AMOUNT / 4);
        givenValidQueueState(queueState, 0, 0);
        assets = floor + (isToken0 ? queueState.deposit0 : queueState.deposit1);
        requestDepositFor(isToken0, owner_, assets);
        settleDeposit(isToken0);
    }

    function setDepositClaimable(
        PoolState memory poolState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0,
        address owner_
    ) internal returns (uint256 assets) {
        // And: The settled deposit credited to the owner's claimable pile.
        assets = setDepositSettled(poolState, range, queueState, isToken0, owner_);
        vm.prank(owner_);
        asyncVaultFor(isToken0).deposit(0, owner_);
    }

    function setRedeemSettled(
        PoolState memory poolState,
        RangeState memory range,
        bool isToken0,
        address owner_,
        uint256 shares
    ) internal returns (uint256 bounded) {
        // And: A redeem worth an asset that the buffer pays, requested and settled.
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        }
        uint256 asset =
            isToken0 ? FixedPointMathLib.fullMulDivUp(1, poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) : 1;
        // And: Where the holding is worth under an asset wei, a hole no bound expresses.
        vm.assume(value > asset);
        uint256 floor = asset.fullMulDivUp(almCore.totalSupply(), value - asset);
        uint256 ceiling = (isToken0
                ? token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0())
                : almCore.bufferAmount1())
        .fullMulDiv(almCore.totalSupply(), value);
        // And: Where the buffer pays under that, a hole no bound expresses.
        vm.assume(floor <= ceiling);
        bounded = bound(shares, floor, ceiling);
        requestRedeemFor(isToken0, owner_, bounded);
        settleRedeem(isToken0);
    }

    function setRedeemClaimable(
        PoolState memory poolState,
        RangeState memory range,
        bool isToken0,
        address owner_,
        uint256 shares
    ) internal returns (uint256 bounded) {
        // And: The settled redeem credited to the owner's claimable pile.
        bounded = setRedeemSettled(poolState, range, isToken0, owner_, shares);
        vm.prank(owner_);
        asyncVaultFor(isToken0).redeem(0, owner_, owner_);
    }
}
