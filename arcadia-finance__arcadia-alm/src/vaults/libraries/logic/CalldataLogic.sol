/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @title Calldata Logic.
 * @author Pragma Labs
 * @notice Decodes the vault's parameters appended to the calldata.
 */
library CalldataLogic {
    /* //////////////////////////////////////////////////////////////
                                 DECODERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Decodes whether the vault's asset is token0 from the parameters appended to the calldata.
     * @return assetIsToken0 True when the vault's asset is token0.
     */
    function decodeAssetIsToken0() internal pure returns (bool assetIsToken0) {
        assembly ("memory-safe") {
            let posOfMetadataSize := sub(calldatasize(), 0x20)
            assetIsToken0 := calldataload(sub(posOfMetadataSize, calldataload(posOfMetadataSize)))
        }
    }

    /**
     * @notice Decodes the vault's core from the parameters appended to the calldata.
     * @return core The core.
     */
    function decodeCore() internal pure returns (address core) {
        assembly ("memory-safe") {
            let posOfMetadataSize := sub(calldatasize(), 0x20)
            core := calldataload(add(sub(posOfMetadataSize, calldataload(posOfMetadataSize)), 0x20))
        }
    }

    /**
     * @notice Decodes the vault's pool from the parameters appended to the calldata.
     * @return pool The Metadex CL pool of the core.
     */
    function decodePool() internal pure returns (address pool) {
        assembly ("memory-safe") {
            let posOfMetadataSize := sub(calldatasize(), 0x20)
            pool := calldataload(add(sub(posOfMetadataSize, calldataload(posOfMetadataSize)), 0x40))
        }
    }
}
