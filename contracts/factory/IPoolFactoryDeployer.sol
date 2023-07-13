// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";

interface IPoolFactoryDeployer {
    error PoolFactoryDeployer__NotPoolFactory(address caller);

    /// @notice Deploy a new option pool
    /// @param k The pool key
    /// @return poolAddress The address of the deployed pool
    function deployPool(IPoolFactory.PoolKey calldata k) external returns (address poolAddress);

    /// @notice Calculate the deterministic address deployment of a pool
    function calculatePoolAddress(IPoolFactory.PoolKey calldata k) external view returns (address);
}
