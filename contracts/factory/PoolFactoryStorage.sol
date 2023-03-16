// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

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
        // Discount % per neighboring strike/maturity, 1e18 base
        uint256 discountPerPool;
        // Initialization fee receiver
        address feeReceiver;
        // Number of blocks required to pass before a deposit can be withdrawn
        // (to prevent flash loans and JIT)
        uint256 withdrawalDelay;
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
