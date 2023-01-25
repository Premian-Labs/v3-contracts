// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PoolFactoryStorage {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.PoolFactory");

    struct Layout {
        // Pool Key -> Address
        mapping(bytes32 => address) pools;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function poolKey(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    base,
                    underlying,
                    baseOracle,
                    underlyingOracle,
                    strike,
                    maturity,
                    isCallPool
                )
            );
    }
}
