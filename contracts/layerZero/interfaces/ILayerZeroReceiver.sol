// SPDX-License-Identifier: MIT

pragma solidity >=0.8.20;

interface ILayerZeroReceiver {
    /// @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    /// @param srcChainId The source endpoint identifier
    /// @param srcAddress The source sending contract address from the source chain
    /// @param nonce The ordered message nonce
    /// @param payload The signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64 nonce,
        bytes calldata payload
    ) external;
}
