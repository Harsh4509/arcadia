/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { EnumerableSetLib } from "@solady/utils/EnumerableSetLib.sol";
import { Ownable } from "@solady/auth/Ownable.sol";

/**
 * @title ALM Registry.
 * @author Pragma Labs
 * @notice Lists every ALM factory with the lens over its cores.
 */
// forge-lint: disable-next-item(reentrancy-events)
contract ALMRegistry is Ownable {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    // The lens over each registered factory's cores.
    mapping(address factory => address lens) public factoryToLens;
    // The registered factories.
    EnumerableSetLib.AddressSet internal factorySet;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event FactoryRegistered(address indexed factory, address indexed lens);
    event FactoryUnregistered(address indexed factory);

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error AlreadyRegistered();
    error NotRegistered();
    error ZeroAddress();

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        _initializeOwner(owner_);
    }

    /* //////////////////////////////////////////////////////////////
                              REGISTRATION
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Registers a factory with its lens.
     * @param factory The ALM factory.
     * @param lens The lens over the factory's cores.
     */
    function registerFactory(address factory, address lens) external onlyOwner {
        if (factory == address(0) || lens == address(0)) revert ZeroAddress();
        if (!factorySet.add(factory)) revert AlreadyRegistered();
        factoryToLens[factory] = lens;

        emit FactoryRegistered(factory, lens);
    }

    /**
     * @notice Unregisters a factory.
     * @param factory The ALM factory.
     * @dev Hides the factory from discovery only, its cores keep working.
     */
    function unregisterFactory(address factory) external onlyOwner {
        if (!factorySet.remove(factory)) revert NotRegistered();
        delete factoryToLens[factory];

        emit FactoryUnregistered(factory);
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Whether a factory is registered.
     * @param factory The ALM factory.
     * @return registered True when it is.
     */
    function isFactoryRegistered(address factory) external view returns (bool registered) {
        registered = factorySet.contains(factory);
    }

    /**
     * @notice The number of registered factories.
     * @return length The number of factories.
     */
    function factoriesLength() external view returns (uint256 length) {
        length = factorySet.length();
    }

    /**
     * @notice A registered factory.
     * @param index The position in the set.
     * @return factory The ALM factory, zero past the end.
     */
    function factoriesAt(uint256 index) external view returns (address factory) {
        factory = index < factorySet.length() ? factorySet.at(index) : address(0);
    }

    /**
     * @notice Every registered factory.
     * @return factories_ The ALM factories.
     */
    function factories() external view returns (address[] memory factories_) {
        factories_ = factorySet.values();
    }
}
