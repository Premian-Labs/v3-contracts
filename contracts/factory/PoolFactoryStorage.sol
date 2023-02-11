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
        // Discount lattice for strike
        mapping(bytes32 => uint256) strikeCount;
        // Discount lattice for maturity
        mapping(bytes32 => uint256) maturityCount;
        // Chainlink price oracle for the ETH/USD pair
        address ethUsdOracle;
        // Discount % per neighboring strike/maturity, 1e18 base
        uint256 discountPerPool;
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
                    k.baseOracle,
                    k.quoteOracle,
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
                    k.baseOracle,
                    k.quoteOracle,
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
                    k.baseOracle,
                    k.quoteOracle,
                    k.maturity,
                    k.isCallPool
                )
            );
    }
}
