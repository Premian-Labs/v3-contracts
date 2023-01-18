// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPosition {
    error Position__InvalidAssetChange();
    error Position__InvalidContractsToCollateralRatio();
    error Position__InvalidOrderType();
    error Position__LowerGreaterOrEqualUpper();
}
