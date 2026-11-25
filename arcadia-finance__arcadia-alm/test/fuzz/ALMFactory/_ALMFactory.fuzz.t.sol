/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "../ALMCore/_ALMCore.fuzz.t.sol";
import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactoryExtension } from "../../utils/extensions/ALMFactoryExtension.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { ALMSyncExtension } from "../../../src/vaults/ALMSyncExtension.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { RouterTrampoline } from "../../utils/fixtures/asset-managers/RouterTrampoline.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Common logic needed by all "ALMFactory" fuzz tests, over the real core and vaults the factory deploys.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract ALMFactory_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMFactoryExtension internal almFactory;
    ALMCore internal core;
    Vaults internal vaults;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function creationCodes() internal pure returns (CreationCodes memory codes) {
        codes = CreationCodes({
            core: type(ALMCore).creationCode,
            keeperExtension: type(ALMKeeperExtension).creationCode,
            adminExtension: type(ALMAdminExtension).creationCode,
            syncVault: type(ALMVaultSync).creationCode,
            asyncVault: type(ALMVaultAsync).creationCode,
            syncExtension: type(ALMSyncExtension).creationCode
        });
    }

    function setFactoryState(PoolState memory poolState) internal {
        deployStack(false, poolState);
        int24 tickUpper = bandTick(poolState.tickSpacing);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), -tickUpper, tickUpper, poolState.liquidityPool);
        mintPosition(pool, users.liquidityProvider, -tickUpper, tickUpper, amount0, amount1);

        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        routerTrampoline = new RouterTrampoline();
        almFactory = deployFactory(creationCodes(), address(routerTrampoline), users.owner, users.steward);
        factory = address(almFactory);
        vm.label(factory, "ALMFactory");

        vm.startPrank(users.owner);
        almFactory.setAdmin(users.admin);
        almFactory.setGuardian(users.guardian);
        almFactory.setSteward(users.steward);
        vm.stopPrank();
    }

    function setCoreCreated() internal {
        core = ALMCore(
            createInThreeTransactions(almFactory, address(pool), creationCodes(), users.steward, users.feeRecipient)
        );
        vaults = almFactory.getVaults(address(core));
        vm.label(address(core), "ALMCore");
    }

    function deploymentsFor(uint8 contracts, CreationCodes memory codes)
        internal
        pure
        returns (Deployment[] memory deployments)
    {
        uint8 syncContracts = uint8((1 << Constants.CONTRACT_SYNC_VAULT0) | (1 << Constants.CONTRACT_SYNC_VAULT1));
        uint8 asyncContracts = uint8((1 << Constants.CONTRACT_ASYNC_VAULT0) | (1 << Constants.CONTRACT_ASYNC_VAULT1));
        Deployment[] memory all = new Deployment[](6);
        uint256 count;
        if (contracts & syncContracts != 0) all[count++] = Deployment(contracts & syncContracts, codes.syncVault);
        if (contracts & asyncContracts != 0) all[count++] = Deployment(contracts & asyncContracts, codes.asyncVault);
        if (contracts & (1 << Constants.CONTRACT_SYNC_EXTENSION) != 0) {
            all[count++] = Deployment(uint8(1 << Constants.CONTRACT_SYNC_EXTENSION), codes.syncExtension);
        }
        if (contracts & (1 << Constants.CONTRACT_KEEPER_EXTENSION) != 0) {
            all[count++] = Deployment(uint8(1 << Constants.CONTRACT_KEEPER_EXTENSION), codes.keeperExtension);
        }
        if (contracts & (1 << Constants.CONTRACT_ADMIN_EXTENSION) != 0) {
            all[count++] = Deployment(uint8(1 << Constants.CONTRACT_ADMIN_EXTENSION), codes.adminExtension);
        }
        if (contracts & (1 << Constants.CONTRACT_CORE) != 0) {
            all[count++] = Deployment(uint8(1 << Constants.CONTRACT_CORE), codes.core);
        }

        deployments = new Deployment[](count);
        for (uint256 i; i < count; ++i) {
            deployments[i] = all[i];
        }
    }

    function setCoreStarted() internal {
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, new Deployment[](0));
    }

    function setSyncVaultsCreated() internal {
        setCoreStarted();
        vm.prank(users.steward);
        almFactory.resumeCore(address(pool), syncVaultDeployments(creationCodes()));
    }

    function setHalfCreated(bool withSyncVaults) internal returns (address core_) {
        if (withSyncVaults) setSyncVaultsCreated();
        else setCoreStarted();
        core_ = contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, creationCodes().core);
    }

    function setVaultConfigured() internal {
        vm.startPrank(users.admin);
        almFactory.setDeviation(
            address(core),
            Constants.TWAP_WINDOW,
            Constants.WIDE_DEVIATION,
            Constants.WIDE_DEVIATION,
            Constants.OPEN_TWAP_DEVIATION
        );
        almFactory.setRangeCap(address(core), ConfigLib.MAX_RANGE_CAP);
        almFactory.setTotalCap(address(core), type(uint128).max);
        almFactory.setPerUserCap(address(core), type(uint128).max);
        vm.stopPrank();
    }

    function transactionGasUsed(uint256 frameGas, bytes memory data) internal pure returns (uint256 used) {
        uint256 tokens;
        for (uint256 i; i < data.length; ++i) {
            tokens += data[i] == 0 ? 1 : Constants.NONZERO_BYTE_TOKENS;
        }
        used = FixedPointMathLib.max(
            Constants.TX_BASE_GAS + Constants.STANDARD_TOKEN_GAS * tokens + frameGas,
            Constants.TX_BASE_GAS + Constants.FLOOR_TOKEN_GAS * tokens
        );
    }

    function contractOfKind(uint256 kind, uint256 member) internal pure returns (uint8 contract_) {
        // A sync vault, an async vault or the core, by kind.
        kind = bound(kind, 0, 2);
        contract_ = kind == 2
            ? Constants.CONTRACT_CORE
            : uint8(
                (kind == 0 ? Constants.CONTRACT_SYNC_VAULT0 : Constants.CONTRACT_ASYNC_VAULT0) + bound(member, 0, 1)
            );
    }

    function roleAt(uint256 pick) internal view returns (address role) {
        pick = bound(pick, 0, 3);
        if (pick == 0) role = users.owner;
        else if (pick == 1) role = users.admin;
        else if (pick == 2) role = users.guardian;
        else role = users.steward;
    }

    function vaultsOf(Vaults memory vaults_) internal pure returns (address[4] memory list) {
        list = [vaults_.syncVault0, vaults_.syncVault1, vaults_.asyncVault0, vaults_.asyncVault1];
    }
}
