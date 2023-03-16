// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IRegistryInternal {
    /// @notice Thrown when trying to add pair where addresses are the same
    error Registry__TokensAreSame(address tokenA, address tokenB);
}
