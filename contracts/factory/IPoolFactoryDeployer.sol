// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

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
