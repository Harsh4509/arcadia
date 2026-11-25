/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory } from "../../../src/factory/ALMFactory.sol";
import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { ALMFactoryExtension } from "../../utils/extensions/ALMFactoryExtension.sol";
import { BaseFactory } from "../../../src/factory/abstracts/base/BaseFactory.sol";
import { CodeHashes } from "../../../src/factory/types/CodeHashes.sol";
import { Ownable } from "@solady/auth/Ownable.sol";
import { RouterTrampoline } from "../../utils/fixtures/asset-managers/RouterTrampoline.sol";

/**
 * @notice Fuzz tests for the constructor of contract "ALMFactory".
 */
contract Constructor_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_constructor_ZeroAddress(uint8 zeroed) public {
        // Given: The leaf stack, and one of the five chain addresses left at zero.
        deployMetadex(false);
        deployMetadexCL();
        zeroed = uint8(bound(zeroed, 0, 4));
        address[5] memory chain = [
            address(POSITION_MANAGER),
            makeAddr("routerTrampoline"),
            address(leafVoter),
            address(clGaugeFactory),
            rewardToken
        ];
        chain[zeroed] = address(0);

        // When: Deploying the factory.
        // Then: It reverts.
        vm.expectRevert(BaseFactory.ZeroAddress.selector);
        new ALMFactoryExtension(
            chain[0], chain[1], chain[2], chain[3], chain[4], false, users.owner, codeHashesOf(creationCodes())
        );
    }

    function testFuzz_Revert_constructor_ZeroAddress_Owner(
        address positionManager,
        address routerTrampoline_,
        address gaugeFactory,
        address rewardToken_,
        bytes32[6] memory hashes
    ) public {
        // Given: The leaf stack and four non-zero chain addresses.
        deployMetadex(false);
        deployMetadexCL();
        vm.assume(positionManager != address(0));
        vm.assume(routerTrampoline_ != address(0));
        vm.assume(gaugeFactory != address(0));
        vm.assume(rewardToken_ != address(0));

        // When: Deploying the factory with no owner.
        // Then: It reverts.
        vm.expectRevert(BaseFactory.ZeroAddress.selector);
        new ALMFactoryExtension(
            positionManager,
            routerTrampoline_,
            address(leafVoter),
            gaugeFactory,
            rewardToken_,
            false,
            address(0),
            CodeHashes(hashes[0], hashes[1], hashes[2], hashes[3], hashes[4], hashes[5])
        );
    }

    function testFuzz_Success_constructor_Leaf(
        address positionManager,
        address routerTrampoline_,
        address gaugeFactory,
        address rewardToken_,
        address owner_
    ) public {
        // Given: The leaf stack and five non-zero addresses.
        deployMetadex(false);
        deployMetadexCL();
        vm.assume(positionManager != address(0));
        vm.assume(routerTrampoline_ != address(0));
        vm.assume(gaugeFactory != address(0));
        vm.assume(rewardToken_ != address(0));
        vm.assume(owner_ != address(0));

        // When: Deploying the factory.
        vm.expectEmit();
        emit Ownable.OwnershipTransferred(address(0), owner_);
        ALMFactoryExtension factory_ = new ALMFactoryExtension(
            positionManager,
            routerTrampoline_,
            address(leafVoter),
            gaugeFactory,
            rewardToken_,
            false,
            owner_,
            codeHashesOf(creationCodes())
        );

        // Then: The five argument immutables are set.
        assertEq(factory_.POSITION_MANAGER(), positionManager);
        assertEq(factory_.ROUTER_TRAMPOLINE(), routerTrampoline_);
        assertEq(factory_.LEAF_VOTER_(), address(leafVoter));
        assertEq(factory_.GAUGE_FACTORY_(), gaugeFactory);
        assertEq(factory_.REWARD_TOKEN_(), rewardToken_);

        // And: The derived immutable matches the leaf stack.
        assertEq(factory_.FACTORY_REGISTRY_(), address(factoryRegistry));

        // And: The owner is set and the other roles are unset.
        assertEq(factory_.owner(), owner_);
        assertEq(factory_.admin(), address(0));
        assertEq(factory_.guardian(), address(0));
        assertEq(factory_.steward(), address(0));
    }

    function testFuzz_Success_constructor_StoresTheCodeHashes(bytes32[6] memory hashes) public {
        // Given: The leaf stack and a router trampoline.
        deployMetadex(false);
        deployMetadexCL();
        routerTrampoline = new RouterTrampoline();

        // When: Deploying the factory with six code hashes.
        ALMFactoryExtension factory_ = new ALMFactoryExtension(
            address(POSITION_MANAGER),
            address(routerTrampoline),
            address(leafVoter),
            address(clGaugeFactory),
            rewardToken,
            false,
            users.owner,
            CodeHashes(hashes[0], hashes[1], hashes[2], hashes[3], hashes[4], hashes[5])
        );

        // Then: Each is stored as the hash of its kind.
        assertEq(factory_.CORE_CODE_HASH(), hashes[0]);
        assertEq(factory_.KEEPER_EXTENSION_CODE_HASH(), hashes[1]);
        assertEq(factory_.ADMIN_EXTENSION_CODE_HASH(), hashes[2]);
        assertEq(factory_.SYNC_VAULT_CODE_HASH(), hashes[3]);
        assertEq(factory_.ASYNC_VAULT_CODE_HASH(), hashes[4]);
        assertEq(factory_.SYNC_EXTENSION_CODE_HASH(), hashes[5]);
    }

    function testFuzz_Success_constructor_StoresTheBlockClock(bool arbBlockNumber) public {
        // Given: The leaf stack and a router trampoline.
        deployMetadex(false);
        deployMetadexCL();
        routerTrampoline = new RouterTrampoline();

        // When: Deploying the factory with either block clock.
        ALMFactoryExtension factory_ = new ALMFactoryExtension(
            address(POSITION_MANAGER),
            address(routerTrampoline),
            address(leafVoter),
            address(clGaugeFactory),
            rewardToken,
            arbBlockNumber,
            users.owner,
            codeHashesOf(creationCodes())
        );

        // Then: The cores it creates receive it.
        assertEq(factory_.parameters().arbBlockNumber, arbBlockNumber);
    }

    function testFuzz_Success_constructor_KeeperSetEmpty(address core, address keeper) public {
        // Given: The leaf stack.
        deployMetadex(false);
        deployMetadexCL();

        // When: Deploying the factory.
        ALMFactoryExtension factory_ =
            deployFactory(creationCodes(), address(new RouterTrampoline()), users.owner, users.steward);

        // Then: No account is in the keeper set.
        assertFalse(factory_.isKeeper(core, keeper));
    }
}
