// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolProxy} from "../pool/PoolProxy.sol";

contract PoolFactory is IPoolFactory {
    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle
    ) external returns (address callPool, address putPool) {
        // ToDo : Check if pools already exists

        callPool = address(
            new PoolProxy(
                address(this),
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                true
            )
        );

        putPool = address(
            new PoolProxy(
                address(this),
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                false
            )
        );

        // ToDo : Save pool addresses in storage
    }
}
