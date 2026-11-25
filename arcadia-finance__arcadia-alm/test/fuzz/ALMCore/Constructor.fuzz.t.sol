/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtensionExtension } from "../../utils/extensions/ALMAdminExtensionExtension.sol";
import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMCoreViewLogicExtension } from "../../utils/extensions/ALMCoreViewLogicExtension.sol";
import { ALMKeeperExtensionExtension } from "../../utils/extensions/ALMKeeperExtensionExtension.sol";
import { Constants } from "../../utils/Constants.sol";
import { CoreParameters } from "../../../src/core/types/CoreParameters.sol";
import { DeployerMock } from "../../utils/mocks/DeployerMock.sol";
import { Deployment } from "../../../src/factory/types/Deployment.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { RouterTrampoline } from "../../utils/fixtures/asset-managers/RouterTrampoline.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the constructor of contract "ALMCore" and of the extensions created with it.
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract Constructor_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_constructor_InvalidExtension_ZeroKeeper(PoolState memory poolState) public {
        // Given: A deployer naming a zero keeper extension and a deployed admin one.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        CoreParameters memory params = almCore.coreParameters_(users.feeRecipient);
        params.keeperExtension = address(0);
        DeployerMock deployer_ = new DeployerMock();
        deployer_.setParameters(params);

        // When: Deploying a core from it.
        // Then: It reverts.
        vm.expectRevert(ALMCore.InvalidExtension.selector);
        deployer_.deploy(type(ALMCore).creationCode);
    }

    function testFuzz_Revert_constructor_InvalidExtension_ZeroAdmin(PoolState memory poolState) public {
        // Given: A deployer naming a zero admin extension and a deployed keeper one.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        CoreParameters memory params = almCore.coreParameters_(users.feeRecipient);
        params.adminExtension = address(0);
        DeployerMock deployer_ = new DeployerMock();
        deployer_.setParameters(params);

        // When: Deploying a core from it.
        // Then: It reverts.
        vm.expectRevert(ALMCore.InvalidExtension.selector);
        deployer_.deploy(type(ALMCore).creationCode);
    }

    function testFuzz_Revert_constructor_InvalidExtension_CodelessKeeper(
        PoolState memory poolState,
        address keeperExtension
    ) public {
        // Given: A deployer naming a codeless keeper extension and a deployed admin one.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(keeperExtension.code.length == 0);
        CoreParameters memory params = almCore.coreParameters_(users.feeRecipient);
        params.keeperExtension = keeperExtension;
        DeployerMock deployer_ = new DeployerMock();
        deployer_.setParameters(params);

        // When: Deploying a core from it.
        // Then: It reverts.
        vm.expectRevert(ALMCore.InvalidExtension.selector);
        deployer_.deploy(type(ALMCore).creationCode);
    }

    function testFuzz_Revert_constructor_InvalidExtension_CodelessAdmin(
        PoolState memory poolState,
        address adminExtension
    ) public {
        // Given: A deployer naming a codeless admin extension and a deployed keeper one.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(adminExtension.code.length == 0);
        CoreParameters memory params = almCore.coreParameters_(users.feeRecipient);
        params.adminExtension = adminExtension;
        DeployerMock deployer_ = new DeployerMock();
        deployer_.setParameters(params);

        // When: Deploying a core from it.
        // Then: It reverts.
        vm.expectRevert(ALMCore.InvalidExtension.selector);
        deployer_.deploy(type(ALMCore).creationCode);
    }

    function testFuzz_Success_constructor_ReadsTheFactorysParameters(uint256 sqrtPrice) public {
        // Given: The leaf stack with a pool and an activated gauge.
        deployMetadex(false);
        deployMetadexCL();
        pool = createPool(
            address(token0),
            address(token1),
            TICK_SPACING,
            uint160(bound(sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1)),
            OBSERVATION_CARDINALITY
        );
        gauge = createGauge(pool, true);

        // And: A factory with the chain's router trampoline.
        routerTrampoline = new RouterTrampoline();
        deployer = deployFactory(extensionCreationCodes(), address(routerTrampoline), users.owner, users.steward);

        // When: The factory creates a core over that pool.
        almCore = ALMCoreExtension(
            createInThreeTransactions(
                deployer, address(pool), extensionCreationCodes(), users.steward, users.feeRecipient
            )
        );

        // Then: The factory and the pool state are the core's creation parameters.
        assertEq(almCore.factory_(), address(deployer));
        assertEq(almCore.pool_(), address(pool));
        assertEq(almCore.token0(), pool.token0());
        assertEq(almCore.token1(), pool.token1());
        assertEq(almCore.tickSpacing(), TICK_SPACING);
        assertEq(almCore.gauge(), address(gauge));

        // And: The chain immutables come from the factory.
        assertEq(almCore.POSITION_MANAGER_(), address(POSITION_MANAGER));
        assertEq(almCore.ROUTER_TRAMPOLINE_(), address(routerTrampoline));
        assertEq(almCore.LEAF_VOTER_(), address(leafVoter));
        assertEq(almCore.GAUGE_FACTORY_(), address(clGaugeFactory));
        assertEq(almCore.REWARD_TOKEN_(), receiptToken);

        // And: The core is not yet initialized.
        assertEq(almCore.totalSupply(), 0);
        assertEq(almCore.decimals(), 18);
    }

    function testFuzz_Success_constructor_SetsTheRewardPoolToken(uint256 sqrtPrice, bool withToken0) public {
        // Given: The leaf stack.
        deployMetadex(false);
        deployMetadexCL();

        // And: A pool of the reward token as its token0 or token1, and an active gauge.
        address other = withToken0 ? address(uint160(receiptToken) + 1) : address(uint160(receiptToken) - 1);
        deployCodeTo("ERC20Mock.sol:ERC20Mock", abi.encode("Token B", "TKNB", uint8(6)), other);
        pool = createPool(
            receiptToken,
            other,
            TICK_SPACING,
            uint160(bound(sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1)),
            OBSERVATION_CARDINALITY
        );
        gauge = createGauge(pool, true);

        // And: A factory with the chain's router trampoline.
        routerTrampoline = new RouterTrampoline();
        deployer = deployFactory(extensionCreationCodes(), address(routerTrampoline), users.owner, users.steward);

        // When: The factory creates a core over that pool.
        almCore = ALMCoreExtension(
            createInThreeTransactions(
                deployer, address(pool), extensionCreationCodes(), users.steward, users.feeRecipient
            )
        );

        // Then: The core records which pool token is the reward token.
        assertEq(new ALMCoreViewLogicExtension().getConfig(address(almCore)).rewardPoolToken, withToken0 ? 1 : 2);
    }

    function testFuzz_Success_constructor_LeavesTheRewardPoolTokenUnset_BelowBothPoolTokens(
        PoolState memory poolState,
        uint160 rewardToken
    ) public {
        // Given: A deployer naming a reward token below both pool tokens.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        CoreParameters memory params = almCore.coreParameters_(users.feeRecipient);
        params.rewardToken = address(uint160(bound(rewardToken, 0, uint160(params.token0) - 1)));
        DeployerMock deployer_ = new DeployerMock();
        deployer_.setParameters(params);

        // When: Deploying a core from it.
        address core = deployer_.deploy(type(ALMCore).creationCode);

        // Then: The core records no pool token as the reward token.
        assertEq(new ALMCoreViewLogicExtension().getConfig(core).rewardPoolToken, 0);
    }

    function testFuzz_Success_constructor_CopiesTheBlockClock(PoolState memory poolState, bool arbBlockNumber) public {
        // Given: A deployer whose parameters carry either block clock.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        CoreParameters memory params = almCore.coreParameters_(users.feeRecipient);
        params.arbBlockNumber = arbBlockNumber;
        DeployerMock deployer_ = new DeployerMock();
        deployer_.setParameters(params);

        // When: Deploying a core from it.
        address core = deployer_.deploy(type(ALMCore).creationCode);

        // Then: The core counts penalty windows with that clock.
        assertEq(new ALMCoreViewLogicExtension().getConfig(core).arbBlockNumber, arbBlockNumber);
    }

    function testFuzz_Success_constructor_SetsTheShareToken(uint256 sqrtPrice) public {
        // Given: The leaf stack with a pool and an activated gauge.
        deployMetadex(false);
        deployMetadexCL();
        pool = createPool(
            address(token0),
            address(token1),
            TICK_SPACING,
            uint160(bound(sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1)),
            OBSERVATION_CARDINALITY
        );
        gauge = createGauge(pool, true);

        // And: A factory with the chain's router trampoline.
        routerTrampoline = new RouterTrampoline();
        deployer = deployFactory(extensionCreationCodes(), address(routerTrampoline), users.owner, users.steward);

        // When: The factory creates a core over that pool.
        almCore = ALMCoreExtension(
            createInThreeTransactions(
                deployer, address(pool), extensionCreationCodes(), users.steward, users.feeRecipient
            )
        );

        // Then: The fee recipient is set and the share token is named after the pool.
        string memory pair = string.concat(ERC20(almCore.token0()).symbol(), "/", ERC20(almCore.token1()).symbol());
        assertEq(almCore.feeRecipient_(), users.feeRecipient);
        assertEq(almCore.name(), string.concat("Arcadia ALM ", pair));
        assertEq(almCore.symbol(), string.concat("aLP-", pair));
        assertEq(almCore.decimals(), 18);
        assertEq(almCore.totalSupply(), 0);

        // And: Both lookups answer with the vaults created at their own contracts only.
        CreationCodes memory codes = extensionCreationCodes();
        address factory_ = address(deployer);
        assertEq(
            almCore.vault(almCore.token0()),
            contractAddress(factory_, address(pool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault)
        );
        assertEq(
            almCore.vault(almCore.token1()),
            contractAddress(factory_, address(pool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault)
        );
        assertEq(almCore.vault(address(almCore)), address(0));
        assertEq(
            almCore.asyncVault_(almCore.token0()),
            contractAddress(factory_, address(pool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault)
        );
        assertEq(
            almCore.asyncVault_(almCore.token1()),
            contractAddress(factory_, address(pool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        );
        assertEq(almCore.asyncVault_(address(almCore)), address(0));
    }

    function testFuzz_Success_constructor_EmitsVaultsSet(uint256 sqrtPrice) public {
        // Given: A factory over a pool, all but the async vaults and the core created.
        deployMetadex(false);
        deployMetadexCL();
        pool = createPool(
            address(token0),
            address(token1),
            TICK_SPACING,
            uint160(bound(sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1)),
            OBSERVATION_CARDINALITY
        );
        gauge = createGauge(pool, true);
        routerTrampoline = new RouterTrampoline();
        CreationCodes memory codes = extensionCreationCodes();
        deployer = deployFactory(codes, address(routerTrampoline), users.owner, users.steward);
        vm.startPrank(users.steward);
        deployer.createCore(address(pool), users.feeRecipient, new Deployment[](0));
        deployer.resumeCore(address(pool), syncVaultDeployments(codes));

        // When: The last transaction creates the async vaults and the core.
        address factory_ = address(deployer);
        vm.expectEmit(contractAddress(factory_, address(pool), Constants.CONTRACT_CORE, codes.core));
        emit IALMCoreEvents.VaultsSet(
            contractAddress(factory_, address(pool), Constants.CONTRACT_SYNC_VAULT0, codes.syncVault),
            contractAddress(factory_, address(pool), Constants.CONTRACT_SYNC_VAULT1, codes.syncVault),
            contractAddress(factory_, address(pool), Constants.CONTRACT_ASYNC_VAULT0, codes.asyncVault),
            contractAddress(factory_, address(pool), Constants.CONTRACT_ASYNC_VAULT1, codes.asyncVault)
        );
        deployer.resumeCore(address(pool), asyncVaultAndCoreDeployments(codes));
        vm.stopPrank();

        // Then: The core sits where CREATE2 puts its creation code.
        assertEq(
            deployer.getCore(address(pool)),
            contractAddress(factory_, address(pool), Constants.CONTRACT_CORE, codes.core)
        );
    }

    function testFuzz_Success_constructor_ChainImmutablesEqualTheCores_KeeperExtension(PoolState memory poolState)
        public
    {
        // Given: A core deployed with both extensions.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMKeeperExtensionExtension keeperExtension = ALMKeeperExtensionExtension(almCore.KEEPER_EXTENSION_());

        // When: Reading every immutable of the core and of its extension.
        (address[16] memory expected, int24 expectedTickSpacing) = almCore.immutables_();
        (address[16] memory values, int24 tickSpacing_) = keeperExtension.immutables_();

        // Then: The extension holds the core's chain immutables.
        for (uint256 i; i < 6; ++i) {
            assertEq(values[i], expected[i]);
        }

        // And: The core's two extension addresses.
        assertEq(values[14], expected[14]);
        assertEq(values[15], expected[15]);

        // And: No pool immutable, since it serves every pool.
        for (uint256 i = 6; i < 14; ++i) {
            assertEq(values[i], address(0));
        }
        assertEq(tickSpacing_, 0);
        assertNotEq(expectedTickSpacing, 0);

        // And: Its own address as SELF.
        assertEq(keeperExtension.SELF_(), address(keeperExtension));
    }

    function testFuzz_Success_constructor_ChainImmutablesEqualTheCores_AdminExtension(PoolState memory poolState)
        public
    {
        // Given: A core deployed with both extensions.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMAdminExtensionExtension adminExtension = ALMAdminExtensionExtension(almCore.ADMIN_EXTENSION_());

        // When: Reading every immutable of the core and of its extension.
        (address[16] memory expected, int24 expectedTickSpacing) = almCore.immutables_();
        (address[16] memory values, int24 tickSpacing_) = adminExtension.immutables_();

        // Then: The extension holds the core's chain immutables.
        for (uint256 i; i < 6; ++i) {
            assertEq(values[i], expected[i]);
        }

        // And: The core's two extension addresses.
        assertEq(values[14], expected[14]);
        assertEq(values[15], expected[15]);

        // And: No pool immutable, since it serves every pool.
        for (uint256 i = 6; i < 14; ++i) {
            assertEq(values[i], address(0));
        }
        assertEq(tickSpacing_, 0);
        assertNotEq(expectedTickSpacing, 0);

        // And: Its own address as SELF.
        assertEq(adminExtension.SELF_(), address(adminExtension));
    }

    function testFuzz_Success_constructor_LeavesItsOwnStorageEmpty_KeeperExtension(PoolState memory poolState) public {
        // Given: A core deployed with both extensions.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address keeperExtension = almCore.KEEPER_EXTENSION_();

        // When: Reading what the core's constructor writes, on the extension itself.
        // Then: No fee recipient, name or symbol was written.
        assertEq(vm.load(keeperExtension, bytes32(uint256(STATE_SLOT) + 3)), bytes32(0));
        assertEq(vm.load(keeperExtension, bytes32(uint256(STATE_SLOT) + 11)), bytes32(0));
        assertEq(vm.load(keeperExtension, bytes32(uint256(STATE_SLOT) + 12)), bytes32(0));

        // And: No position manager approval was given.
        assertEq(token0.allowance(keeperExtension, address(POSITION_MANAGER)), 0);
        assertEq(token1.allowance(keeperExtension, address(POSITION_MANAGER)), 0);
    }

    function testFuzz_Success_constructor_LeavesItsOwnStorageEmpty_AdminExtension(PoolState memory poolState) public {
        // Given: A core deployed with both extensions.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address adminExtension = almCore.ADMIN_EXTENSION_();

        // When: Reading what the core's constructor writes, on the extension itself.
        // Then: No fee recipient, name or symbol was written.
        assertEq(vm.load(adminExtension, bytes32(uint256(STATE_SLOT) + 3)), bytes32(0));
        assertEq(vm.load(adminExtension, bytes32(uint256(STATE_SLOT) + 11)), bytes32(0));
        assertEq(vm.load(adminExtension, bytes32(uint256(STATE_SLOT) + 12)), bytes32(0));

        // And: No position manager approval was given.
        assertEq(token0.allowance(adminExtension, address(POSITION_MANAGER)), 0);
        assertEq(token1.allowance(adminExtension, address(POSITION_MANAGER)), 0);
    }
}
