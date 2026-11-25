/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../src/core/ALMCore.sol";
import { ALMFactory_Fuzz_Test } from "../fuzz/ALMFactory/_ALMFactory.fuzz.t.sol";
import { ALMFactoryHandler } from "./handlers/ALMFactoryHandler.sol";
import { ALMVaultSync } from "../../src/vaults/ALMVaultSync.sol";
import { BaseFactory } from "../../src/factory/abstracts/base/BaseFactory.sol";
import { Constants } from "../utils/Constants.sol";
import { ConfigLib } from "../../src/core/libraries/state/ConfigLib.sol";
import { CoreParameters } from "../../src/core/types/CoreParameters.sol";
import { ERC20Mock } from "../utils/mocks/ERC20Mock.sol";
import { ICLPool } from "../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Invariant_Test } from "./Invariant.t.sol";
import { VaultParameters } from "../../src/vaults/types/VaultParameters.sol";
import { Vaults } from "../../src/core/types/Vaults.sol";

/**
 * @notice Invariant tests for contract "ALMFactory".
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local)
contract ALMFactory_Invariant_Test is Invariant_Test, ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    uint256 internal constant POOLS = 4;

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMFactoryHandler internal handler;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(Invariant_Test, ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
        PoolState memory poolState;
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        setFactoryState(poolState);

        address[] memory candidates = new address[](POOLS);
        candidates[0] = address(pool);
        for (uint256 i = 1; i < POOLS; ++i) {
            ERC20Mock tokenA = new ERC20Mock("Token A", "TKNA", 18);
            ERC20Mock tokenB = new ERC20Mock("Token B", "TKNB", 18);
            ICLPool candidate =
                createPool(address(tokenA), address(tokenB), TICK_SPACING, SQRT_PRICE_ONE_X96, OBSERVATION_CARDINALITY);
            createGauge(candidate, true);
            candidates[i] = address(candidate);
        }
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        address[] memory accounts = new address[](5);
        (accounts[0], accounts[1], accounts[2], accounts[3], accounts[4]) =
        (users.owner, users.admin, users.guardian, users.steward, users.unprivilegedAddress);
        handler = new ALMFactoryHandler(almFactory, users.feeRecipient, Constants.TWAP_WINDOW, candidates, accounts);
        targetContract(address(handler));
    }

    /* //////////////////////////////////////////////////////////////
                                 PROBES
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_probe_EveryCreationPathRuns(uint256 poolSeed, uint256 amount, address receiver) public {
        // Given: The suite's factory, candidate pools and handler.

        // When: A pool is created in two steps, created again, resumed again, and seeded.
        handler.createCore(poolSeed, Constants.CORE_DEPENDENCIES);
        handler.resumeCore(poolSeed, Constants.ALL_CONTRACTS);
        handler.createCore(poolSeed, Constants.ALL_CONTRACTS);
        handler.resumeCore(poolSeed, Constants.ALL_CONTRACTS);
        handler.seedCore(poolSeed, amount, amount, amount, receiver);

        // Then: One core was created and the repeats reverted for their own reasons.
        assertEq(handler.ghostCreated(), 1);
        assertEq(handler.reverts(handler.createCore.selector), 1);
        assertEq(handler.reverts(handler.resumeCore.selector), 1);
        assertEq(handler.ghostUnexpectedReverts(), 0);
        invariant_oneCorePerPool();
        invariant_creationRevertsOnlyForExpectedReasons();
        invariant_aSeededCoreHoldsItsSeedWithTheDeadShares();
    }

    function testFuzz_Success_probe_IllegalDeploymentOrdersAreTried(uint256 poolSeed) public {
        // Given: A pool pending with one vault deployed.
        handler.createCore(poolSeed, 1);

        // When: Its core is deployed before the other vaults, and its vault again.
        handler.resumeIllegally(poolSeed, false);
        handler.resumeIllegally(poolSeed, true);

        // Then: Both were tried and refused for their expected reasons.
        assertEq(handler.ghostIllegalDeploymentsTried(), 2);
        assertEq(handler.revertsByReason(handler.resumeIllegally.selector, BaseFactory.ContractsMissing.selector), 1);
        assertEq(handler.revertsByReason(handler.resumeIllegally.selector, BaseFactory.ContractExists.selector), 1);
        invariant_illegalDeploymentsAreRefused();
        invariant_creationRevertsOnlyForExpectedReasons();
    }

    function testFuzz_Success_probe_EveryRoleAndForwarderPathRuns(uint256 poolSeed, uint256 amount, uint256 pick)
        public
    {
        // Given: A created core.
        handler.createCore(poolSeed, Constants.ALL_CONTRACTS);

        // When: Holders and a stranger move a role, a keeper, the pause and a forwarder.
        handler.setRole(1, 4, 0);
        handler.revokeGuardian(3);
        handler.setKeeper(poolSeed, 4, 1, true);
        handler.setKeeper(poolSeed, 4, 3, false);
        handler.setPaused(poolSeed, 3, true);
        handler.forward(poolSeed, 1, bound(pick, 0, 8), amount);
        handler.setRole(0, 4, 4);
        handler.setPaused(poolSeed, 4, false);

        // Then: The holders' calls went through and the stranger's were refused.
        assertEq(handler.ghostRoleMoves(), 2);
        assertEq(handler.ghostKeeperMoves(), 2);
        assertEq(handler.ghostPauseMoves(), 1);
        assertEq(handler.reverts(handler.setPaused.selector), 1);
        invariant_onlyRoleHoldersMoveRoleGatedValues();
        invariant_aPauseReachesTheCoreAndItsFourVaults();
    }

    /* //////////////////////////////////////////////////////////////
                               INVARIANTS
    ////////////////////////////////////////////////////////////// */

    function invariant_vaultsAreAllSetOrAllUnset() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address[4] memory list = vaultsOf(almFactory.getVaults(almFactory.getCore(handler.candidateAt(i))));
            bool set = list[0] != address(0);
            for (uint256 j = 1; j < 4; ++j) {
                assertEq(list[j] != address(0), set);
            }
        }
    }

    function invariant_everyCoreKeepsItsRangesWithinItsCaps() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address core_ = almFactory.getCore(handler.candidateAt(i));
            if (core_ == address(0)) continue;

            uint256 length = coreViewLogic.decodeRanges(coreViewLogic.readRangeWords(core_)).length;
            assertLe(length, ConfigLib.MAX_RANGE_CAP);
            assertLe(length, coreViewLogic.getConfig(core_).rangeCap);
        }
    }

    function invariant_factoryHoldsNothing() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address core_ = almFactory.getCore(handler.candidateAt(i));
            if (core_ == address(0)) continue;

            Vaults memory vaults_ = almFactory.getVaults(core_);
            assertEq(ERC20Mock(ALMVaultSync(vaults_.syncVault0).asset()).balanceOf(address(almFactory)), 0);
            assertEq(ERC20Mock(ALMVaultSync(vaults_.syncVault1).asset()).balanceOf(address(almFactory)), 0);
            assertEq(ALMCore(payable(core_)).balanceOf(address(almFactory)), 0);
        }
    }

    function invariant_oneCorePerPool() public view {
        uint256 created;
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            if (almFactory.getCore(handler.candidateAt(i)) != address(0)) ++created;
        }

        assertEq(created, handler.ghostCreated());
    }

    function invariant_everyRegisteredPoolResolvesToItsCore() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address candidate = handler.candidateAt(i);
            address core_ = almFactory.getCore(candidate);
            if (core_ == address(0)) continue;

            assertTrue(almFactory.isCore(core_));
            assertEq(
                core_, contractAddress(address(almFactory), candidate, Constants.CONTRACT_CORE, creationCodes().core)
            );
        }
    }

    function invariant_everyContractOfACreatedPoolAtItsAddress() public view {
        CreationCodes memory codes = creationCodes();
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address candidate = handler.candidateAt(i);
            if (almFactory.getCore(candidate) == address(0)) continue;

            for (uint8 contract_; contract_ <= Constants.CONTRACT_CORE; ++contract_) {
                address pool_ = uint8(1 << contract_) & Constants.EXTENSION_CONTRACTS != 0 ? address(0) : candidate;
                bytes memory code = deploymentsFor(uint8(1 << contract_), codes)[0].creationCode;
                assertGt(contractAddress(address(almFactory), pool_, contract_, code).code.length, 0);
            }
        }
    }

    function invariant_isCoreOnlyOnceComplete() public view {
        CreationCodes memory codes = creationCodes();
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address candidate = handler.candidateAt(i);
            address core_ = contractAddress(address(almFactory), candidate, Constants.CONTRACT_CORE, codes.core);
            (uint8 contractsDeployed, address feeRecipient) = almFactory.pending(candidate);

            assertEq(almFactory.isCore(core_), core_.code.length > 0);
            if (feeRecipient == address(0)) continue;
            assertFalse(almFactory.isCore(core_));
            assertEq(almFactory.getCore(candidate), address(0));
            assertEq(contractsDeployed & (1 << Constants.CONTRACT_CORE), 0);
        }
    }

    function invariant_creationRevertsOnlyForExpectedReasons() public view {
        assertEq(handler.ghostUnexpectedReverts(), 0);
    }

    function invariant_illegalDeploymentsAreRefused() public view {
        assertEq(handler.ghostIllegalDeploymentsAccepted(), 0);
    }

    function invariant_aLiveCoreNeverReturnsToPending() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address candidate = handler.candidateAt(i);
            if (!handler.ghostLive(candidate)) continue;
            (, address feeRecipient) = almFactory.pending(candidate);

            assertTrue(almFactory.getCore(candidate) != address(0));
            assertEq(feeRecipient, address(0));
        }
    }

    function invariant_onlyRoleHoldersMoveRoleGatedValues() public view {
        assertEq(handler.ghostUnauthorizedAccepted(), 0);
        assertEq(almFactory.admin(), handler.ghostAdmin());
        assertEq(almFactory.guardian(), handler.ghostGuardian());
        assertEq(almFactory.steward(), handler.ghostSteward());
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address core_ = almFactory.getCore(handler.candidateAt(i));
            for (uint256 j; j < handler.accountsLength(); ++j) {
                address account = handler.accountAt(j);
                assertEq(almFactory.isKeeper(core_, account), handler.ghostIsKeeper(core_, account));
            }
        }
    }

    function invariant_aPauseReachesTheCoreAndItsFourVaults() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address core_ = almFactory.getCore(handler.candidateAt(i));
            if (core_ == address(0)) continue;

            bool paused = handler.ghostPaused(core_);
            Vaults memory vaults_ = almFactory.getVaults(core_);
            assertEq(coreViewLogic.getConfig(core_).paused, paused);
            assertEq(ALMVaultSync(vaults_.syncVault0).paused(), paused);
            assertEq(ALMVaultSync(vaults_.syncVault1).paused(), paused);
            assertEq(ALMVaultSync(vaults_.asyncVault0).paused(), paused);
            assertEq(ALMVaultSync(vaults_.asyncVault1).paused(), paused);
        }
    }

    function invariant_aSeededCoreHoldsItsSeedWithTheDeadShares() public view {
        for (uint256 i; i < handler.candidatesLength(); ++i) {
            address core_ = almFactory.getCore(handler.candidateAt(i));
            if (core_ == address(0)) continue;

            uint256 shares = handler.ghostSeededShares(core_);
            address receiver = handler.ghostSeedReceiver(core_);
            assertEq(ALMCore(payable(core_)).totalSupply(), shares);
            if (shares == 0) continue;
            if (receiver == address(1)) {
                assertEq(ALMCore(payable(core_)).balanceOf(address(1)), shares);
            } else {
                assertEq(ALMCore(payable(core_)).balanceOf(address(1)), Constants.DEAD_SHARES);
                assertEq(ALMCore(payable(core_)).balanceOf(receiver), shares - Constants.DEAD_SHARES);
            }
        }
    }

    function invariant_parametersZeroOutsideACreationCall() public view {
        CoreParameters memory params = almFactory.parameters();
        VaultParameters memory vaultParams = almFactory.vaultParameters();

        assertEq(params.pool, address(0));
        assertEq(params.token0, address(0));
        assertEq(params.feeRecipient, address(0));
        assertEq(vaultParams.core, address(0));
        assertEq(vaultParams.pool, address(0));
        assertEq(vaultParams.syncExtension, address(0));
    }
}
