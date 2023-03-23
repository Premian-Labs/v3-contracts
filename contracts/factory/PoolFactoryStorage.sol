// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";

library PoolFactoryStorage {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.PoolFactory");

    struct Layout {
        // Pool Key -> Address
        mapping(bytes32 => address) pools;
        // Pool Address -> Whether this is a pool or not
        mapping(address => bool) isPool;
        // Pool Key -> Count (Discount lattice for strike)
        mapping(bytes32 => uint256) strikeCount;
        // Pool Key -> Count (Discount lattice for maturity)
        mapping(bytes32 => uint256) maturityCount;
        // Discount % per neighboring strike/maturity | 18 decimals
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

    function poolKey(
        IPoolFactory.PoolKey memory k
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    k.base,
                    k.quote,
                    k.oracleAdapter,
                    k.strike,
                    k.maturity,
                    k.isCallPool
                )
            );
    }

    function strikeKey(
        IPoolFactory.PoolKey memory k
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    k.base,
                    k.quote,
                    k.oracleAdapter,
                    k.strike,
                    k.isCallPool
                )
            );
    }

    function maturityKey(
        IPoolFactory.PoolKey memory k
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    k.base,
                    k.quote,
                    k.oracleAdapter,
                    k.maturity,
                    k.isCallPool
                )
            );
    }
}
