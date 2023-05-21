// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";

library PoolFactoryStorage {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.PoolFactory");

    struct Layout {
        mapping(bytes32 key => address pool) pools;
        mapping(address pool => bool) isPool;
        mapping(bytes32 key => uint256 count) strikeCount;
        mapping(bytes32 key => uint256 count) maturityCount;
        // Discount % per neighboring strike/maturity (18 decimals)
        UD60x18 discountPerPool;
        // Initialization fee receiver
        address feeReceiver;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /// @notice Returns the encoded pool key using the pool key `k`
    function poolKey(IPoolFactory.PoolKey memory k) internal pure returns (bytes32) {
        return keccak256(abi.encode(k.base, k.quote, k.oracleAdapter, k.strike, k.maturity, k.isCallPool));
    }

    /// @notice Returns the encoded strike key using the pool key `k`
    function strikeKey(IPoolFactory.PoolKey memory k) internal pure returns (bytes32) {
        return keccak256(abi.encode(k.base, k.quote, k.oracleAdapter, k.strike, k.isCallPool));
    }

    /// @notice Returns the encoded maturity key using the pool key `k`
    function maturityKey(IPoolFactory.PoolKey memory k) internal pure returns (bytes32) {
        return keccak256(abi.encode(k.base, k.quote, k.oracleAdapter, k.maturity, k.isCallPool));
    }
}
