// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";

interface IInitFeeCalculator {
    /// @notice Calculates the initialization fee for a pool
    /// @param k The pool key
    /// @param discountPerPool The discount per pool (18 decimals)
    /// @param maturityCount The count of neighboring maturities
    /// @param strikeCount The count of neighboring strikes
    /// @return The initialization fee (18 decimals)
    function initializationFee(
        IPoolFactory.PoolKey memory k,
        UD60x18 discountPerPool,
        uint256 maturityCount,
        uint256 strikeCount
    ) external view returns (UD60x18);
}
