// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolFactory {
    event PairCreated(
        address indexed base,
        address indexed underlying,
        address baseOracle,
        address underlyingOracle,
        address callPool,
        address putPool
    );

    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle
    ) external returns (address callPool, address putPool);
}
