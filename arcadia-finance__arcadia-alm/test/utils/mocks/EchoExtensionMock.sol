/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

/**
 * @notice An extension that returns the address it runs at, its caller and the calldata it received.
 */
contract EchoExtensionMock {
    fallback() external {
        bytes memory echo = abi.encode(address(this), msg.sender, msg.data);
        assembly ("memory-safe") {
            return(add(echo, 0x20), mload(echo))
        }
    }
}
