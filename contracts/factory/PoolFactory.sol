// SPDX-License-Identifier: UNLICENSED

// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy} from "../pool/PoolProxy.sol";

contract PoolFactory is IPoolFactory {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    error PoolFactory__ZeroAddress();
    error PoolFactory__IdenticalAddresses();
    error PoolFactory__PoolExists();

    // ToDo : See if we deploy one per strike / maturity or if we can group into one contract
    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle
    ) external returns (address callPool, address putPool) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        if (base == underlying) revert PoolFactory__IdenticalAddresses();

        if (base == address(0) || underlying == address(0))
            revert PoolFactory__ZeroAddress();

        if (
            l.pools[base][underlying][baseOracle][underlyingOracle][true] !=
            address(0)
        ) revert PoolFactory__PoolExists();

        // Deterministic pool addresses
        bytes32 callSalt = keccak256(
            abi.encodePacked(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                true
            )
        );
        bytes32 putSalt = keccak256(
            abi.encodePacked(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                false
            )
        );

        callPool = address(
            new PoolProxy{salt: callSalt}(
                address(this),
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                true
            )
        );

        putPool = address(
            new PoolProxy{salt: putSalt}(
                address(this),
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                false
            )
        );

        l.pools[base][underlying][baseOracle][underlyingOracle][
            true
        ] = callPool;
        l.pools[base][underlying][baseOracle][underlyingOracle][
            false
        ] = putPool;

        // ToDo : See if we really need `l.poolList`
        l.poolList.push(callPool);
        l.poolList.push(putPool);

        // ToDo : See if we really need `l.isPool`
        l.isPool[callPool] = true;
        l.isPool[putPool] = true;

        emit PairCreated(
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            callPool,
            putPool
        );
    }
}
