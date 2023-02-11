// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PoolFactoryStorage {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.PoolFactory");

    struct Layout {
        // Pool Key -> Address
        mapping(bytes32 => address) pools;
        // Discount lattice for strike
        mapping(bytes32 => uint256) strikeCount;
        // Discount lattice for maturity
        mapping(bytes32 => uint256) maturityCount;

        // Discount % per neighboring strike/maturity, 1e18 base
        uint256 discountPerPool;
        // Controller of discountPerPool
        address discountAdmin;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function poolKey(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    base,
                    quote,
                    baseOracle,
                    quoteOracle,
                    strike,
                    maturity,
                    isCallPool
                )
            );
    }

    function strikeKey(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        bool isCallPool
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    base,
                    quote,
                    baseOracle,
                    quoteOracle,
                    strike,
                    isCallPool
                )
            );
    }

    function maturityKey(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint64 maturity,
        bool isCallPool
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    base,
                    quote,
                    baseOracle,
                    quoteOracle,
                    maturity,
                    isCallPool
                )
            );
    }
}
