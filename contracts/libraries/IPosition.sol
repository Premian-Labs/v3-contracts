// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IPosition {
    error Position__InvalidOrderType();
    error Position__InvalidPositionUpdate();
    error Position__LowerGreaterOrEqualUpper();
}
