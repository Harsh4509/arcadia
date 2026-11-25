/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { EchoExtensionMock } from "../../utils/mocks/EchoExtensionMock.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { RevertingExtensionMock } from "../../utils/mocks/RevertingExtensionMock.sol";

/**
 * @notice Fuzz tests for the stubs of contract "ALMVaultSync".
 */
contract Stubs_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_stubs_UnknownSelector(PoolState memory poolState, bool isToken0, bytes memory data)
        public
    {
        // Given: A vault over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Calling the vault with a selector neither it nor its extension declares.
        (bool success, bytes memory result) =
            address(vault).call(abi.encodePacked(bytes4(keccak256("unknown()")), data));

        // Then: It reverts without data.
        assertFalse(success);
        assertEq(result.length, 0);
    }

    function testFuzz_Revert_stubs_BubblesTheExtensionsRevert(
        PoolState memory poolState,
        bool isToken0,
        address account,
        address caller
    ) public {
        // Given: A vault whose sync extension reverts with the calldata it receives.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);
        vm.etch(
            deployer.computeAddress(address(0), Constants.CONTRACT_SYNC_EXTENSION),
            address(new RevertingExtensionMock()).code
        );
        bytes memory callData = abi.encodeCall(IALMSyncExtension.maxRedeem, (account));

        // When: Calling a view stub on the vault.
        vm.prank(caller);
        (bool success, bytes memory result) = address(vault).call(callData);

        // Then: It reverts with the extension's revert data, the parameters appended.
        bytes memory metadata = abi.encode(isToken0, address(almCore), address(pool));
        assertFalse(success);
        assertEq(result, bytes.concat(callData, metadata, abi.encode(metadata.length)));
    }

    function testFuzz_Success_stubs_ForwardsToTheSyncExtension(
        PoolState memory poolState,
        bool isToken0,
        address account,
        uint256 amount,
        address caller
    ) public {
        // Given: A vault whose sync extension echoes its address, caller and calldata.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);
        address extension = deployer.computeAddress(address(0), Constants.CONTRACT_SYNC_EXTENSION);
        vm.etch(extension, address(new EchoExtensionMock()).code);

        // And: The vault's parameters in the ERC-3448 layout.
        bytes memory metadata = abi.encode(isToken0, address(almCore), address(pool));

        // And: Each view stub.
        bytes[] memory calls = new bytes[](7);
        calls[0] = abi.encodeCall(IALMSyncExtension.totalAssets, ());
        calls[1] = abi.encodeCall(IALMSyncExtension.convertToShares, (amount));
        calls[2] = abi.encodeCall(IALMSyncExtension.convertToAssets, (amount));
        calls[3] = abi.encodeCall(IALMSyncExtension.maxDeposit, (account));
        calls[4] = abi.encodeCall(IALMSyncExtension.maxMint, (account));
        calls[5] = abi.encodeCall(IALMSyncExtension.maxRedeem, (account));
        calls[6] = abi.encodeCall(IALMSyncExtension.maxWithdraw, (account));

        for (uint256 i; i < calls.length; ++i) {
            // When: Calling the view stub on the vault.
            vm.prank(caller);
            (bool success, bytes memory result) = address(vault).call(calls[i]);

            // Then: The extension ran at its address, called by the vault with them.
            assertTrue(success);
            (address self, address sender, bytes memory received) = abi.decode(result, (address, address, bytes));
            assertEq(self, extension);
            assertEq(sender, address(vault));
            assertEq(received, bytes.concat(calls[i], metadata, abi.encode(metadata.length)));
        }
    }

    function testFuzz_Success_stubs_ServesTheSyncExtensionViews(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amount,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded token1 vault holding a range, and an amount of up to the supply.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        IALMSyncExtension viaVault = IALMSyncExtension(address(seededVault(coreState, range, false)));
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        amount = bound(amount, 0, almCore.totalSupply());

        // And: The sync extension, and the token1 vault's ERC-3448 parameters.
        address direct = deployer.computeAddress(address(0), Constants.CONTRACT_SYNC_EXTENSION);
        bytes memory metadata = abi.encode(false, address(almCore), address(pool));
        bytes memory suffix = bytes.concat(metadata, abi.encode(metadata.length));

        // And: Each view.
        bytes[] memory calls = new bytes[](7);
        calls[0] = abi.encodeCall(IALMSyncExtension.totalAssets, ());
        calls[1] = abi.encodeCall(IALMSyncExtension.convertToShares, (amount));
        calls[2] = abi.encodeCall(IALMSyncExtension.convertToAssets, (amount));
        calls[3] = abi.encodeCall(IALMSyncExtension.maxDeposit, (users.unprivilegedAddress));
        calls[4] = abi.encodeCall(IALMSyncExtension.maxMint, (users.unprivilegedAddress));
        calls[5] = abi.encodeCall(IALMSyncExtension.maxRedeem, (users.steward));
        calls[6] = abi.encodeCall(IALMSyncExtension.maxWithdraw, (users.steward));

        for (uint256 i; i < calls.length; ++i) {
            // When: Reading the view through the vault, and on the extension directly.
            (bool okViaVault, bytes memory resultViaVault) = address(viaVault).staticcall(calls[i]);
            (bool okDirect, bytes memory resultDirect) = direct.staticcall(bytes.concat(calls[i], suffix));

            // Then: Both answer the same.
            assertTrue(okViaVault);
            assertTrue(okDirect);
            assertEq(resultViaVault, resultDirect);
        }
    }

    function testFuzz_Success_stubs_EachVaultGetsItsOwnAssetSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 amount,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range, and an amount of up to the supply.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        amount = bound(amount, 0, almCore.totalSupply());

        // And: The asynchronous vault over the same token, carrying its own conversions.
        ALMVaultAsync sameToken = isToken0 ? asyncVault : secondAsyncVault;

        // When: Reading the conversions through the synchronous vault.
        IALMSyncExtension viaVault = IALMSyncExtension(address(vault));

        // Then: They are those of the vault's own asset.
        assertEq(viaVault.totalAssets(), sameToken.totalAssets());
        assertEq(viaVault.convertToShares(amount), sameToken.convertToShares(amount));
        assertEq(viaVault.convertToAssets(amount), sameToken.convertToAssets(amount));
    }

    function testFuzz_Success_stubs_PausedVaultAnswersZero(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A token1 vault seeded with it.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, false);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A holder whose maxRedeem is above zero.
        uint256 maxRedeem = IALMSyncExtension(address(vault)).maxRedeem(users.steward);
        assertGt(maxRedeem, 0);

        // When: The factory pauses the vault.
        vm.prank(factory);
        vault.setPaused(true);

        // Then: The view through the vault answers zero.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);

        // And: The extension, called with the parameters, answers the unpaused amount.
        address extension = deployer.computeAddress(address(0), Constants.CONTRACT_SYNC_EXTENSION);
        bytes memory metadata = abi.encode(false, address(almCore), address(pool));
        (bool success, bytes memory result) = extension.staticcall(
            bytes.concat(
                abi.encodeCall(IALMSyncExtension.maxRedeem, (users.steward)), metadata, abi.encode(metadata.length)
            )
        );
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), maxRedeem);
    }
}
