// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy} from "../pool/PoolProxy.sol";

contract PoolFactory is IPoolFactory {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    function getDeploymentAddress(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (address) {
        return
            _getDeploymentAddress(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            );
    }

    function _getDeploymentAddress(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) internal view returns (address) {
        bytes memory args = abi.encode(
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            strike,
            maturity,
            isCallPool
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), // 0
                address(this), // address of factory contract
                keccak256(args), // salt
                // The contract bytecode
                keccak256(abi.encodePacked(type(PoolProxy).creationCode, args))
            )
        );

        // Cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function isPoolDeployed(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (bool) {
        return
            _isPoolDeployed(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            );
    }

    function _isPoolDeployed(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) internal view returns (bool) {
        return
            _getDeploymentAddress(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            ).code.length > 0;
    }

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

        if (
            _isPoolDeployed(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            )
        ) revert PoolFactory__PoolAlreadyDeployed();

        // Deterministic pool addresses
        bytes32 salt = keccak256(
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

        poolAddress = address(
            new PoolProxy{salt: salt}(
                address(this),
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            )
        );

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
