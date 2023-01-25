// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy} from "../pool/PoolProxy.sol";

contract PoolFactory is IPoolFactory {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    address internal immutable DIAMOND;

    constructor(address diamond) {
        DIAMOND = diamond;
    }

    /// @inheritdoc IPoolFactory
    function isPoolDeployed(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (bool) {
        bytes32 poolKey = PoolFactoryStorage.poolKey(
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            strike,
            maturity,
            isCallPool
        );
        return _isPoolDeployed(poolKey);
    }

    function _isPoolDeployed(bytes32 poolKey) internal view returns (bool) {
        return PoolFactoryStorage.layout().pools[poolKey] != address(0);
    }

    /// @inheritdoc IPoolFactory
    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external returns (address poolAddress) {
        if (base == underlying || baseOracle == underlyingOracle)
            revert PoolFactory__IdenticalAddresses();

        // ToDo : Enforce some maturity increment ?
        if (maturity <= block.timestamp) revert PoolFactory__InvalidMaturity();
        // ToDo : Enforce some strike increment ?
        if (strike == 0) revert PoolFactory__InvalidStrike();

        if (base == address(0) || underlying == address(0))
            revert PoolFactory__ZeroAddress();

        bytes32 poolKey = PoolFactoryStorage.poolKey(
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            strike,
            maturity,
            isCallPool
        );

        if (_isPoolDeployed(poolKey)) revert PoolFactory__PoolAlreadyDeployed();

        poolAddress = address(
            new PoolProxy(
                DIAMOND,
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            )
        );

        PoolFactoryStorage.layout().pools[poolKey] = poolAddress;

        emit PoolDeployed(
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            strike,
            maturity,
            poolAddress
        );
    }
}
