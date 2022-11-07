// SPDX-License-Identifier: UNLICENSED



// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library PoolFactoryStorage {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.PoolFactory");

    struct Layout {
        address feeRecipient;
        // base => underlying => baseOracle => underlyingOracle => isCallPool => pool
        mapping(address => mapping(address => mapping(address => mapping(address => mapping(bool => address))))) pools;
        address[] poolList;
        mapping(address => bool) isPool;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
