/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMAdminExtensionExtension } from "../../utils/extensions/ALMAdminExtensionExtension.sol";
import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { ALMKeeperExtensionExtension } from "../../utils/extensions/ALMKeeperExtensionExtension.sol";
import { BaseExtension } from "../../../src/core/abstracts/base/BaseExtension.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { CoreImmutables } from "../../../src/core/types/CoreImmutables.sol";
import { EchoExtensionMock } from "../../utils/mocks/EchoExtensionMock.sol";
import { ERC20Share } from "../../../src/core/abstracts/tokens/ERC20Share.sol";
import { RevertingExtensionMock } from "../../utils/mocks/RevertingExtensionMock.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Fuzz tests for the stubs of contract "ALMCore" and for direct calls to the extensions they delegate to.
 */
// forge-lint: disable-next-item(unchecked-call, unused-return)
contract Stubs_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    bytes internal metadata;

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMKeeperExtensionExtension internal keeperExtension;
    ALMAdminExtensionExtension internal adminExtension;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    function deployCore() internal override {
        ALMCore_Fuzz_Test.deployCore();
        keeperExtension = ALMKeeperExtensionExtension(almCore.KEEPER_EXTENSION_());
        adminExtension = ALMAdminExtensionExtension(almCore.ADMIN_EXTENSION_());
        vm.label(address(keeperExtension), "ALMKeeperExtension");
        vm.label(address(adminExtension), "ALMAdminExtension");
        Vaults memory vaults_ = deployer.getVaults(address(almCore));
        metadata = abi.encode(
            CoreImmutables({
                tickSpacing: pool.tickSpacing(),
                pool: address(pool),
                token0: pool.token0(),
                token1: pool.token1(),
                gauge: address(gauge),
                asyncVault0: asyncVault0,
                asyncVault1: asyncVault1,
                syncVault0: vaults_.syncVault0,
                syncVault1: vaults_.syncVault1
            })
        );
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setRangeCap_BubblesTheExtensionsRevert(uint8 newRangeCap, address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setRangeCap() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(abi.encodeCall(ALMCore.setRangeCap, (newRangeCap)), metadata, abi.encode(metadata.length))
        );
        almCore.setRangeCap(newRangeCap);
    }

    function testFuzz_Revert_setPerUserCap_BubblesTheExtensionsRevert(uint256 newPerUserCap, address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setPerUserCap() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(abi.encodeCall(ALMCore.setPerUserCap, (newPerUserCap)), metadata, abi.encode(metadata.length))
        );
        almCore.setPerUserCap(newPerUserCap);
    }

    function testFuzz_Revert_setTotalCap_BubblesTheExtensionsRevert(uint256 newTotalCap, address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setTotalCap() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(abi.encodeCall(ALMCore.setTotalCap, (newTotalCap)), metadata, abi.encode(metadata.length))
        );
        almCore.setTotalCap(newTotalCap);
    }

    function testFuzz_Revert_lowerTotalCap_BubblesTheExtensionsRevert(uint256 newTotalCap, address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling lowerTotalCap() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(abi.encodeCall(ALMCore.lowerTotalCap, (newTotalCap)), metadata, abi.encode(metadata.length))
        );
        almCore.lowerTotalCap(newTotalCap);
    }

    function testFuzz_Revert_lowerPerUserCap_BubblesTheExtensionsRevert(uint256 newPerUserCap, address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling lowerPerUserCap() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(ALMCore.lowerPerUserCap, (newPerUserCap)), metadata, abi.encode(metadata.length)
            )
        );
        almCore.lowerPerUserCap(newPerUserCap);
    }

    function testFuzz_Revert_setPlanLimits_BubblesTheExtensionsRevert(
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval,
        address caller
    ) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setPlanLimits() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(ALMCore.setPlanLimits, (newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval)),
                metadata,
                abi.encode(metadata.length)
            )
        );
        almCore.setPlanLimits(newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval);
    }

    function testFuzz_Revert_pause_BubblesTheExtensionsRevert(address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling pause() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(bytes.concat(abi.encodeCall(ALMCore.pause, ()), metadata, abi.encode(metadata.length)));
        almCore.pause();
    }

    function testFuzz_Revert_unpause_BubblesTheExtensionsRevert(address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling unpause() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(bytes.concat(abi.encodeCall(ALMCore.unpause, ()), metadata, abi.encode(metadata.length)));
        almCore.unpause();
    }

    function testFuzz_Revert_setDeviation_BubblesTheExtensionsRevert(
        uint32 newTwapWindow,
        uint256 maxSpotFromTwap,
        uint256 maxSpotFromTrusted,
        uint256 maxTwapFromTrusted,
        address caller
    ) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setDeviation() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(
                    ALMCore.setDeviation, (newTwapWindow, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted)
                ),
                metadata,
                abi.encode(metadata.length)
            )
        );
        almCore.setDeviation(newTwapWindow, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted);
    }

    function testFuzz_Revert_setProtocolFees_BubblesTheExtensionsRevert(
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient,
        address caller
    ) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setProtocolFees() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(
                    ALMCore.setProtocolFees, (newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient)
                ),
                metadata,
                abi.encode(metadata.length)
            )
        );
        almCore.setProtocolFees(newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_payProtocolFees_BubblesTheExtensionsRevert(address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling payProtocolFees() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(abi.encodeCall(ALMCore.payProtocolFees, ()), metadata, abi.encode(metadata.length))
        );
        almCore.payProtocolFees();
    }

    function testFuzz_Revert_claimEmissions_BubblesTheExtensionsRevert(address account, address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling claimEmissions() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(abi.encodeCall(ALMCore.claimEmissions, (account)), metadata, abi.encode(metadata.length))
        );
        almCore.claimEmissions(account);
    }

    function testFuzz_Revert_seed_BubblesTheExtensionsRevert(
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        address receiver,
        address caller
    ) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling seed() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(ALMCore.seed, (amount0, amount1, shares, receiver)),
                metadata,
                abi.encode(metadata.length)
            )
        );
        almCore.seed(amount0, amount1, shares, receiver);
    }

    function testFuzz_Revert_execute_BubblesTheExtensionsRevert(
        bytes memory commands,
        bytes[] memory inputs,
        uint160 trustedSqrtPriceX96,
        address caller,
        ConfigState memory configState
    ) public {
        // Given: A keeper extension that reverts with the calldata it receives.
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling execute() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(ALMCore.execute, (commands, inputs, trustedSqrtPriceX96)),
                metadata,
                abi.encode(metadata.length)
            )
        );
        almCore.execute(commands, inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_skim_BubblesTheExtensionsRevert(address caller) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling skim() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(bytes.concat(abi.encodeCall(ALMCore.skim, ()), metadata, abi.encode(metadata.length)));
        almCore.skim();
    }

    function testFuzz_Revert_setOperator_BubblesTheExtensionsRevert(
        address controller,
        address operator,
        bool approved,
        address caller
    ) public {
        // Given: An admin extension that reverts with the calldata it receives.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);

        // When: Calling setOperator() on the core.
        // Then: It bubbles the extension's revert on the calldata plus immutables.
        vm.prank(caller);
        vm.expectRevert(
            bytes.concat(
                abi.encodeCall(ALMCore.setOperator, (controller, operator, approved)),
                metadata,
                abi.encode(metadata.length)
            )
        );
        almCore.setOperator(controller, operator, approved);
    }

    function testFuzz_Revert_execute_OnlyDelegated(
        bytes memory commands,
        bytes[] memory inputs,
        uint160 trustedSqrtPriceX96
    ) public {
        // Given: The keeper, the only caller a plan admits through the core.

        // When: Calling execute() on the extension itself.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(BaseExtension.OnlyDelegated.selector);
        keeperExtension.execute(commands, inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_payProtocolFees_OnlyDelegated(address caller) public {
        // Given: Any caller, as the core admits through its stub.

        // When: Calling payProtocolFees() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseExtension.OnlyDelegated.selector);
        adminExtension.payProtocolFees();
    }

    function testFuzz_Revert_claimEmissions_OnlyDelegated(address caller, address account) public {
        // Given: Any caller, as the core admits through its stub.

        // When: Calling claimEmissions() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseExtension.OnlyDelegated.selector);
        adminExtension.claimEmissions(account);
    }

    function testFuzz_Revert_skim_OnlyDelegated(address caller) public {
        // Given: Any caller, as the core admits through its stub.

        // When: Calling skim() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseExtension.OnlyDelegated.selector);
        adminExtension.skim();
    }

    function testFuzz_Revert_setOperator_OnlyDelegated(
        address caller,
        address controller,
        address operator,
        bool approved
    ) public {
        // Given: Any caller, as the core admits through its stub.

        // When: Calling setOperator() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseExtension.OnlyDelegated.selector);
        adminExtension.setOperator(controller, operator, approved);
    }

    function testFuzz_Revert_allowance_NotSupported_KeeperExtension(address owner_, address spender) public {
        // Given: An extension deployed beside the core.

        // When: Calling allowance() on the extension itself.
        // Then: It reverts.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.allowance(owner_, spender);
    }

    function testFuzz_Revert_approve_NotSupported_KeeperExtension(address caller, address spender, uint256 amount)
        public
    {
        // Given: An extension deployed beside the core.

        // When: Calling approve() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.approve(spender, amount);
    }

    function testFuzz_Revert_transfer_NotSupported_KeeperExtension(address caller, address to, uint256 amount) public {
        // Given: An extension deployed beside the core.

        // When: Calling transfer() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.transfer(to, amount);
    }

    function testFuzz_Revert_transferFrom_NotSupported_KeeperExtension(
        address caller,
        address from,
        address to,
        uint256 amount
    ) public {
        // Given: An extension deployed beside the core.

        // When: Calling transferFrom() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.transferFrom(from, to, amount);
    }

    function testFuzz_Revert_nonces_NotSupported_KeeperExtension(address owner_) public {
        // Given: An extension deployed beside the core.

        // When: Calling nonces() on the extension itself.
        // Then: It reverts.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.nonces(owner_);
    }

    function testFuzz_Revert_permit_NotSupported_KeeperExtension(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        // Given: An extension deployed beside the core.

        // When: Calling permit() on the extension itself.
        // Then: It reverts.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.permit(owner_, spender, value, deadline, v, r, s);
    }

    function testFuzz_Revert_DOMAIN_SEPARATOR_NotSupported_KeeperExtension(address caller) public {
        // Given: An extension deployed beside the core.

        // When: Calling DOMAIN_SEPARATOR() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        keeperExtension.DOMAIN_SEPARATOR();
    }

    function testFuzz_Revert_allowance_NotSupported_AdminExtension(address owner_, address spender) public {
        // Given: An extension deployed beside the core.

        // When: Calling allowance() on the extension itself.
        // Then: It reverts.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.allowance(owner_, spender);
    }

    function testFuzz_Revert_approve_NotSupported_AdminExtension(address caller, address spender, uint256 amount)
        public
    {
        // Given: An extension deployed beside the core.

        // When: Calling approve() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.approve(spender, amount);
    }

    function testFuzz_Revert_transfer_NotSupported_AdminExtension(address caller, address to, uint256 amount) public {
        // Given: An extension deployed beside the core.

        // When: Calling transfer() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.transfer(to, amount);
    }

    function testFuzz_Revert_transferFrom_NotSupported_AdminExtension(
        address caller,
        address from,
        address to,
        uint256 amount
    ) public {
        // Given: An extension deployed beside the core.

        // When: Calling transferFrom() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.transferFrom(from, to, amount);
    }

    function testFuzz_Revert_nonces_NotSupported_AdminExtension(address owner_) public {
        // Given: An extension deployed beside the core.

        // When: Calling nonces() on the extension itself.
        // Then: It reverts.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.nonces(owner_);
    }

    function testFuzz_Revert_permit_NotSupported_AdminExtension(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        // Given: An extension deployed beside the core.

        // When: Calling permit() on the extension itself.
        // Then: It reverts.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.permit(owner_, spender, value, deadline, v, r, s);
    }

    function testFuzz_Revert_DOMAIN_SEPARATOR_NotSupported_AdminExtension(address caller) public {
        // Given: An extension deployed beside the core.

        // When: Calling DOMAIN_SEPARATOR() on the extension itself.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        adminExtension.DOMAIN_SEPARATOR();
    }

    function testFuzz_Success_setRangeCap_ForwardsToTheAdminExtension(uint8 newRangeCap, address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.setRangeCap, (newRangeCap));

        // When: Calling setRangeCap() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_setRangeCap_RunsForACoreAboveItsExtensions(uint8 newRangeCap) public {
        // Given: The core's code at the highest address, above both of its extensions.
        address copy = address(type(uint160).max);
        vm.etch(copy, address(almCore).code);
        newRangeCap = uint8(bound(newRangeCap, 0, ConfigLib.MAX_RANGE_CAP));

        // When: The factory sets the range cap through that core.
        vm.prank(factory);
        ALMCore(payable(copy)).setRangeCap(newRangeCap);

        // Then: The admin extension ran in its context, its delegation check passing.
        assertGt(uint160(copy), uint160(almCore.ADMIN_EXTENSION_()));
        assertEq(ALMCoreExtension(payable(copy)).rangeCap_(), newRangeCap);
    }

    function testFuzz_Success_setPerUserCap_ForwardsToTheAdminExtension(uint256 newPerUserCap, address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.setPerUserCap, (newPerUserCap));

        // When: Calling setPerUserCap() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_setTotalCap_ForwardsToTheAdminExtension(uint256 newTotalCap, address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.setTotalCap, (newTotalCap));

        // When: Calling setTotalCap() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_lowerTotalCap_ForwardsToTheAdminExtension(uint256 newTotalCap, address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.lowerTotalCap, (newTotalCap));

        // When: Calling lowerTotalCap() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_lowerPerUserCap_ForwardsToTheAdminExtension(uint256 newPerUserCap, address caller)
        public
    {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.lowerPerUserCap, (newPerUserCap));

        // When: Calling lowerPerUserCap() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_setPlanLimits_ForwardsToTheAdminExtension(
        uint16 newMaxShortfallBps,
        uint16 newMaxSwapCostBps,
        uint32 newMinPlanInterval,
        address caller
    ) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData =
            abi.encodeCall(ALMCore.setPlanLimits, (newMaxShortfallBps, newMaxSwapCostBps, newMinPlanInterval));

        // When: Calling setPlanLimits() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_pause_ForwardsToTheAdminExtension(address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.pause, ());

        // When: Calling pause() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_unpause_ForwardsToTheAdminExtension(address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.unpause, ());

        // When: Calling unpause() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_setDeviation_ForwardsToTheAdminExtension(
        uint32 newTwapWindow,
        uint256 maxSpotFromTwap,
        uint256 maxSpotFromTrusted,
        uint256 maxTwapFromTrusted,
        address caller
    ) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(
            ALMCore.setDeviation, (newTwapWindow, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted)
        );

        // When: Calling setDeviation() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_setProtocolFees_ForwardsToTheAdminExtension(
        uint16 newProtocolEmissionFeeBps,
        uint16 newProtocolSwapFeeBps,
        address newFeeRecipient,
        address caller
    ) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(
            ALMCore.setProtocolFees, (newProtocolEmissionFeeBps, newProtocolSwapFeeBps, newFeeRecipient)
        );

        // When: Calling setProtocolFees() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_payProtocolFees_ForwardsToTheAdminExtension(address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.payProtocolFees, ());

        // When: Calling payProtocolFees() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_claimEmissions_ForwardsToTheAdminExtension(address account, address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.claimEmissions, (account));

        // When: Calling claimEmissions() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_seed_ForwardsToTheAdminExtension(
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        address receiver,
        address caller
    ) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.seed, (amount0, amount1, shares, receiver));

        // When: Calling seed() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_execute_ForwardsToTheKeeperExtension(
        bytes memory commands,
        bytes[] memory inputs,
        uint160 trustedSqrtPriceX96,
        address caller
    ) public {
        // Given: A keeper extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.execute, (commands, inputs, trustedSqrtPriceX96));

        // When: Calling execute() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The keeper extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_skim_ForwardsToTheAdminExtension(address caller) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.skim, ());

        // When: Calling skim() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_setOperator_ForwardsToTheAdminExtension(
        address controller,
        address operator,
        bool approved,
        address caller
    ) public {
        // Given: An admin extension echoing where it runs, and a reverting one beside it.
        vm.etch(almCore.ADMIN_EXTENSION_(), address(new EchoExtensionMock()).code);
        vm.etch(almCore.KEEPER_EXTENSION_(), address(new RevertingExtensionMock()).code);
        bytes memory callData = abi.encodeCall(ALMCore.setOperator, (controller, operator, approved));

        // When: Calling setOperator() on the core.
        vm.prank(caller);
        (bool success, bytes memory result) = address(almCore).call(callData);

        // Then: The admin extension ran in the core for the caller, immutables appended.
        assertTrue(success);
        assertEq(
            result, abi.encode(address(almCore), caller, bytes.concat(callData, metadata, abi.encode(metadata.length)))
        );
    }

    function testFuzz_Success_balanceOf_ReadsItsOwnEmptyStorage_KeeperExtension(address account, uint256 shares)
        public
    {
        // Given: An account holding aLP on the core.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(account, shares);

        // When: Reading the account's balance on the extension itself.
        uint256 balance = keeperExtension.balanceOf(account);

        // Then: It reads the extension's own storage, where the account holds nothing.
        assertEq(balance, 0);
        assertEq(almCore.balanceOf(account), shares);
    }

    function testFuzz_Success_balanceOf_ReadsItsOwnEmptyStorage_AdminExtension(address account, uint256 shares) public {
        // Given: An account holding aLP on the core.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(account, shares);

        // When: Reading the account's balance on the extension itself.
        uint256 balance = adminExtension.balanceOf(account);

        // Then: It reads the extension's own storage, where the account holds nothing.
        assertEq(balance, 0);
        assertEq(almCore.balanceOf(account), shares);
    }

    function testFuzz_Success_totalSupply_ReadsItsOwnEmptyStorage_KeeperExtension(address account, uint256 shares)
        public
    {
        // Given: aLP minted on the core.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(account, shares);

        // When: Reading the supply on the extension itself.
        uint256 supply = keeperExtension.totalSupply();

        // Then: It reads the extension's own storage, where nothing was minted.
        assertEq(supply, 0);
        assertEq(almCore.totalSupply(), shares);
    }

    function testFuzz_Success_totalSupply_ReadsItsOwnEmptyStorage_AdminExtension(address account, uint256 shares)
        public
    {
        // Given: aLP minted on the core.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(account, shares);

        // When: Reading the supply on the extension itself.
        uint256 supply = adminExtension.totalSupply();

        // Then: It reads the extension's own storage, where nothing was minted.
        assertEq(supply, 0);
        assertEq(almCore.totalSupply(), shares);
    }

    function testFuzz_Success_name_Empty_KeeperExtension(address account, uint256 shares) public {
        // Given: aLP minted on the core, which names its share.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(account, shares);

        // When: Reading the name on the extension itself.
        string memory name_ = keeperExtension.name();

        // Then: It is empty, while the core's names the pair.
        assertEq(name_, "");
        assertEq(almCore.name(), string.concat("Arcadia ALM ", token0.symbol(), "/", token1.symbol()));
    }

    function testFuzz_Success_symbol_Empty_AdminExtension(address account, uint256 shares) public {
        // Given: aLP minted on the core, which gives its share a symbol.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);
        almCore.mintShares(account, shares);

        // When: Reading the symbol on the extension itself.
        string memory symbol_ = adminExtension.symbol();

        // Then: It is empty, while the core's names the pair.
        assertEq(symbol_, "");
        assertEq(almCore.symbol(), string.concat("aLP-", token0.symbol(), "/", token1.symbol()));
    }
}
