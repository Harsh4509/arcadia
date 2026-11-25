/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../ALMCore/_ALMCore.fuzz.t.sol";
import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Constants } from "../../utils/Constants.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Common logic needed by all vault fuzz tests, over a core the four of them are registered on.
 */
// forge-lint: disable-next-item(unused-return)
abstract contract BaseVault_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMVaultSync internal syncVault0;
    ALMVaultSync internal syncVault1;
    ALMVaultAsync internal asyncVault;
    ALMVaultAsync internal secondAsyncVault;
    BaseVault[4] internal vaults;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function deployCore() internal override {
        ALMCore_Fuzz_Test.deployCore();

        Vaults memory vaults_ = deployer.getVaults(address(almCore));
        syncVault0 = ALMVaultSync(vaults_.syncVault0);
        syncVault1 = ALMVaultSync(vaults_.syncVault1);
        asyncVault = ALMVaultAsync(vaults_.asyncVault0);
        secondAsyncVault = ALMVaultAsync(vaults_.asyncVault1);
        vaults = [BaseVault(syncVault0), syncVault1, asyncVault, secondAsyncVault];

        vm.label(address(syncVault0), "ALMVaultSync0");
        vm.label(address(syncVault1), "ALMVaultSync1");
        vm.label(asyncVault0, "ALMVaultAsync0");
        vm.label(asyncVault1, "ALMVaultAsync1");
    }

    function halfCreatedVaults() internal returns (address[4] memory list) {
        int24 tickSpacing = pool.tickSpacing() == TICK_SPACING ? TICK_SPACING / 2 : TICK_SPACING;
        ICLPool secondPool =
            createPool(address(token0), address(token1), tickSpacing, SQRT_PRICE_ONE_X96, OBSERVATION_CARDINALITY);
        createGauge(secondPool, true);
        CreationCodes memory codes = extensionCreationCodes();
        Deployment[] memory asyncVaults = new Deployment[](1);
        asyncVaults[0] = Deployment({
            contracts: uint8((1 << Constants.CONTRACT_ASYNC_VAULT0) | (1 << Constants.CONTRACT_ASYNC_VAULT1)),
            creationCode: codes.asyncVault
        });

        vm.startPrank(users.steward);
        deployer.createCore(address(secondPool), users.feeRecipient, new Deployment[](0));
        deployer.resumeCore(address(secondPool), syncVaultDeployments(codes));
        deployer.resumeCore(address(secondPool), asyncVaults);
        vm.stopPrank();

        address factory_ = address(deployer);
        list = [
            contractAddress(factory_, address(secondPool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault),
            contractAddress(factory_, address(secondPool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault),
            contractAddress(factory_, address(secondPool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault),
            contractAddress(factory_, address(secondPool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        ];
    }

    function setSeededState(CoreState memory coreState, RangeState memory range) internal {
        setCoreState(coreState);
        setRangeState(range);
    }

    function fundVaultCaller(address caller, address asset, uint256 amount, address spender) internal {
        ERC20Mock(asset).mint(caller, amount);
        vm.prank(caller);
        ERC20Mock(asset).approve(spender, amount);
    }

    function vaultFor(bool isToken0) internal view returns (ALMVaultSync vault) {
        vault = isToken0 ? syncVault0 : syncVault1;
    }
}
