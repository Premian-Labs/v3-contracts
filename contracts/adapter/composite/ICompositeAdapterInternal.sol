// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface ICompositeAdapterInternal {
    /// @notice Thrown when the token is the wrapped native token
    error CompositeAdapter__TokenCannotBeWrappedNative();
}
