/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { Constants } from "../../utils/Constants.sol";
import { CoreParameters } from "../../../src/core/types/CoreParameters.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Ownable } from "@solady/auth/Ownable.sol";
import { VaultParameters } from "../../../src/vaults/types/VaultParameters.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Fuzz tests for the function "createCore" of contract "ALMFactory".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract CreateCore_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_createCore_Unauthorized(PoolState memory poolState, address caller) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller is not the steward.
        vm.assume(caller != users.steward);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: Calling createCore().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_Unauthorized_Role(PoolState memory poolState, uint256 pick) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The caller holds another role than the steward.
        address caller = roleAt(pick);
        vm.assume(caller != users.steward);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: Calling createCore().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(Ownable.Unauthorized.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_CoreExists_Pending(PoolState memory poolState, address feeRecipient) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward opens a second one over the same pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreExists.selector);
        almFactory.createCore(address(pool), feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_CoreExists_Created(PoolState memory poolState, address feeRecipient) public {
        // Given: A factory with a core over the pool.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreCreated();
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a second one over the same pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.CoreExists.selector);
        almFactory.createCore(address(pool), feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_InvalidRecipient_Zero(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core with no fee recipient.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.InvalidRecipient.selector);
        almFactory.createCore(address(pool), address(0), deployments);
    }

    function testFuzz_Revert_createCore_InvalidRecipient_Core(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The fee recipient is the core the creation would end in.
        address core_ =
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, creationCodes().core);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core that pays its fees to itself.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.InvalidRecipient.selector);
        almFactory.createCore(address(pool), core_, deployments);
    }

    function testFuzz_Revert_createCore_ObservationCardinalityTooLow(PoolState memory poolState, uint16 cardinalityNext)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A pool of another spacing whose oracle holds too few observations.
        cardinalityNext = uint16(bound(cardinalityNext, 1, almFactory.MIN_OBSERVATION_CARDINALITY() - 1));
        address lowCardinalityPool = address(
            createPool(
                address(token0),
                address(token1),
                poolState.tickSpacing == TICK_SPACING ? TICK_SPACING / 2 : TICK_SPACING,
                SQRT_PRICE_ONE_X96,
                cardinalityNext
            )
        );
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.ObservationCardinalityTooLow.selector);
        almFactory.createCore(lowCardinalityPool, users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_ObservationCardinalityTooLow_OneBelowTheMinimum(PoolState memory poolState)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A pool of another spacing whose oracle is one observation short.
        uint16 cardinalityNext = almFactory.MIN_OBSERVATION_CARDINALITY() - 1;
        address lowCardinalityPool = address(
            createPool(
                address(token0),
                address(token1),
                poolState.tickSpacing == TICK_SPACING ? TICK_SPACING / 2 : TICK_SPACING,
                SQRT_PRICE_ONE_X96,
                cardinalityNext
            )
        );
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.ObservationCardinalityTooLow.selector);
        almFactory.createCore(lowCardinalityPool, users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_GaugeNotValid_NoGauge(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The pool reports no gauge.
        vm.mockCall(address(pool), abi.encodeWithSelector(IMetadexCLPool.gauge.selector), abi.encode(address(0)));
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.GaugeNotValid.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_GaugeNotValid_TargetMismatch(PoolState memory poolState, address target)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The registry maps the pool's gauge to another target.
        vm.assume(target != address(pool));
        vm.mockCall(
            address(factoryRegistry),
            abi.encodeWithSignature("gaugeToTarget(address)", address(gauge)),
            abi.encode(target)
        );
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.GaugeNotValid.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_VoterMismatch(PoolState memory poolState, address secondVoter) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The pool's gauge reports another voter than the factory was built against.
        vm.assume(secondVoter != address(leafVoter));
        vm.mockCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.voter.selector), abi.encode(secondVoter));
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.VoterMismatch.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_GaugeFactoryMismatch(PoolState memory poolState, address secondFactory) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The pool's gauge reports another gauge factory than the factory's.
        vm.assume(secondFactory != address(clGaugeFactory));
        vm.mockCall(
            address(gauge), abi.encodeWithSelector(IMetadexCLGauge.gaugeFactory.selector), abi.encode(secondFactory)
        );
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMFactory.GaugeFactoryMismatch.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_InvalidContracts_EmptyMask(PoolState memory poolState, bytes memory code)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A deployment whose mask names no contract.
        Deployment[] memory deployments = new Deployment[](1);
        deployments[0] = Deployment(0, code);

        // When: The steward creates a core with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_InvalidContracts_TwoKinds(
        PoolState memory poolState,
        uint256 kind,
        uint256 offset,
        uint256 first,
        uint256 second,
        bytes memory code
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A deployment whose mask names two contracts of different kinds.
        kind = bound(kind, 0, 2);
        uint8 contract0 = contractOfKind(kind, first);
        uint8 contract1 = contractOfKind((kind + bound(offset, 1, 2)) % 3, second);
        Deployment[] memory deployments = new Deployment[](1);
        deployments[0] = Deployment(uint8(1 << contract0) | uint8(1 << contract1), code);

        // When: The steward creates a core with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_InvalidContracts_Extension(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A deployment naming an extension, with its creation code.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_EXTENSION, Constants.CONTRACT_ADMIN_EXTENSION));
        Deployment[] memory deployments = deploymentsFor(uint8(1 << contract_), creationCodes());

        // When: The steward creates a core with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.InvalidContracts.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_CodeMismatch(PoolState memory poolState, uint8 contract_, bytes memory code)
        public
    {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A deployment naming one contract with another kind's creation code.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_ASYNC_VAULT1 + 1));
        if (contract_ > Constants.CONTRACT_ASYNC_VAULT1) contract_ = Constants.CONTRACT_CORE;
        Deployment[] memory deployments = new Deployment[](1);
        deployments[0] = Deployment(uint8(1 << contract_), code);
        vm.assume(keccak256(code) != keccak256(deploymentsFor(uint8(1 << contract_), creationCodes())[0].creationCode));

        // When: The steward creates a core with it.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.CodeMismatch.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_ContractExists(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: Two deployments naming the same contract that is not the core.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_ASYNC_VAULT1));
        Deployment[] memory once = deploymentsFor(uint8(1 << contract_), creationCodes());
        Deployment[] memory deployments = new Deployment[](2);
        deployments[0] = once[0];
        deployments[1] = once[0];

        // When: The steward creates a core with them.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.ContractExists.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Revert_createCore_ContractsMissing(PoolState memory poolState, uint8 deployed) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: Batches for any strict subset of the other contracts, then the core.
        deployed = uint8(bound(deployed, 0, Constants.CORE_DEPENDENCIES - 1));
        Deployment[] memory deployments =
            deploymentsFor(deployed | uint8(1 << Constants.CONTRACT_CORE), creationCodes());

        // When: The steward creates a core with them.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseFactory.ContractsMissing.selector);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);
    }

    function testFuzz_Success_createCore_StoresThePendingRecord(
        PoolState memory poolState,
        address feeRecipient,
        uint8 contracts
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A valid recipient, and deployments for any subset but the core.
        vm.assume(feeRecipient != address(0));
        vm.assume(
            feeRecipient
                != contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, creationCodes().core)
        );
        contracts = uint8(bound(contracts, 0, Constants.CORE_DEPENDENCIES));
        Deployment[] memory deployments = deploymentsFor(contracts, creationCodes());

        // When: The steward creates a core with them.
        vm.prank(users.steward);
        almFactory.createCore(address(pool), feeRecipient, deployments);

        // Then: The pending record holds the recipient and every contract deployed.
        (uint8 contractsDeployed, address feeRecipient_) = almFactory.pending(address(pool));
        assertEq(feeRecipient_, feeRecipient);
        assertEq(contractsDeployed, contracts);
    }

    function testFuzz_Success_createCore_ObservationCardinalityAboveTheMinimum(
        PoolState memory poolState,
        uint16 cardinalityNext
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The pool's oracle set to hold more than the minimum observations.
        cardinalityNext = uint16(
            bound(cardinalityNext, almFactory.MIN_OBSERVATION_CARDINALITY() + 1, Constants.MAX_FUZZED_CARDINALITY)
        );
        pool.increaseObservationCardinalityNext(cardinalityNext);
        Deployment[] memory deployments = syncVaultDeployments(creationCodes());

        // When: The steward creates a core over that pool.
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);

        // Then: The pending record holds the recipient.
        (, address feeRecipient_) = almFactory.pending(address(pool));
        assertEq(feeRecipient_, users.feeRecipient);
    }

    function testFuzz_Success_createCore_PoolTokensAboveTheRewardToken(
        PoolState memory poolState,
        address tokenA,
        address tokenB
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: The pool reports two tokens at addresses above the reward token.
        tokenA = address(uint160(bound(uint160(tokenA), uint160(receiptToken) + 1, type(uint160).max)));
        tokenB = address(uint160(bound(uint160(tokenB), uint160(receiptToken) + 1, type(uint160).max)));
        vm.mockCall(address(pool), abi.encodeWithSelector(IMetadexCLPool.token0.selector), abi.encode(tokenA));
        vm.mockCall(address(pool), abi.encodeWithSelector(IMetadexCLPool.token1.selector), abi.encode(tokenB));
        Deployment[] memory deployments = new Deployment[](0);

        // When: The steward creates a core over that pool.
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deployments);

        // Then: The creation is pending for the fee recipient.
        (, address feeRecipient) = almFactory.pending(address(pool));
        assertEq(feeRecipient, users.feeRecipient);
    }

    function testFuzz_Success_createCore_DeploysEachNamedContractAtItsAddress(
        PoolState memory poolState,
        uint8 contracts
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: Batches for any subset of the contracts but the core.
        contracts = uint8(bound(contracts, 0, Constants.CORE_DEPENDENCIES));
        CreationCodes memory codes = creationCodes();

        // When: The steward creates a core with them.
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deploymentsFor(contracts, codes));

        // Then: Every named contract has code at its CREATE2 address, no other has.
        for (uint8 contract_; contract_ <= Constants.CONTRACT_CORE; ++contract_) {
            bytes memory code = deploymentsFor(uint8(1 << contract_), codes)[0].creationCode;
            address predicted = contractAddress(address(almFactory), address(pool), contract_, code);
            assertEq(predicted.code.length > 0, contracts & (1 << contract_) != 0);
            assertEq(almFactory.computeAddress(address(pool), contract_), predicted);
        }
    }

    function testFuzz_Success_createCore_NoCoreBeforeItsStep(PoolState memory poolState, uint8 contracts) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: Batches for any subset of the contracts but the core.
        contracts = uint8(bound(contracts, 0, Constants.CORE_DEPENDENCIES));
        CreationCodes memory codes = creationCodes();

        // When: The steward creates a core with them.
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deploymentsFor(contracts, codes));

        // Then: The pool has no core, and the address the core will take is not one.
        address core_ = contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, codes.core);
        assertEq(almFactory.getCore(address(pool)), address(0));
        assertFalse(almFactory.isCore(core_));
        assertEq(almFactory.getVaults(core_).syncVault0, address(0));
    }

    function testFuzz_Success_createCore_ParametersZeroAfterTheCall(
        PoolState memory poolState,
        uint8 contracts,
        bool complete
    ) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: Batches for every contract, or any subset of them but the core.
        contracts = complete ? Constants.ALL_CONTRACTS : uint8(bound(contracts, 0, Constants.CORE_DEPENDENCIES));

        // When: The steward creates a core with them.
        vm.prank(users.steward);
        almFactory.createCore(address(pool), users.feeRecipient, deploymentsFor(contracts, creationCodes()));

        // Then: The core parameters of the pool read zero.
        CoreParameters memory params = almFactory.parameters();
        assertEq(params.pool, address(0));
        assertEq(params.token0, address(0));
        assertEq(params.gauge, address(0));
        assertEq(params.feeRecipient, address(0));
        assertEq(params.vaults.syncVault0, address(0));

        // And: The vault parameters read zero.
        VaultParameters memory vaultParams = almFactory.vaultParameters();
        assertEq(vaultParams.core, address(0));
        assertEq(vaultParams.pool, address(0));
        assertFalse(vaultParams.assetIsToken0);
        assertEq(vaultParams.syncExtension, address(0));
    }

    function testFuzz_Success_createCore_InOneTransaction(PoolState memory poolState, address feeRecipient) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // And: A valid fee recipient.
        CreationCodes memory codes = creationCodes();
        address core_ = contractAddress(address(almFactory), address(pool), Constants.CONTRACT_CORE, codes.core);
        vm.assume(feeRecipient != address(0) && feeRecipient != core_);
        Vaults memory expected = Vaults(
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault),
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault),
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault),
            contractAddress(address(almFactory), address(pool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        );

        // When: The steward creates every contract, the core last, in one call.
        vm.expectEmit(address(almFactory));
        emit ALMFactory.CoreCreated(
            address(pool), core_, pool.token0(), pool.token1(), address(gauge), feeRecipient, expected
        );
        vm.prank(users.steward);
        almFactory.createCore(address(pool), feeRecipient, deploymentsFor(Constants.ALL_CONTRACTS, codes));

        // Then: The core is registered, and the pending record is deleted.
        assertEq(almFactory.getCore(address(pool)), core_);
        assertTrue(almFactory.isCore(core_));
        (uint8 contractsDeployed, address feeRecipient_) = almFactory.pending(address(pool));
        assertEq(feeRecipient_, address(0));
        assertEq(contractsDeployed, 0);
    }
}
