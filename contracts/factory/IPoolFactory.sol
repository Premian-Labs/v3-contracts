// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolFactory {
    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle
    ) external returns (address callPool, address putPool);
}
