// SPDX-License-Identifier: MIT

pragma solidity >=0.8.20;

interface ILayerZeroUserApplicationConfig {
    /// @notice Set the configuration of the LayerZero messaging library of the specified version
    /// @param version Messaging library version
    /// @param chainId The chainId for the pending config change
    /// @param configType Type of configuration. every messaging library has its own convention.
    /// @param config Configuration in the bytes. can encode arbitrary content.
    function setConfig(uint16 version, uint16 chainId, uint256 configType, bytes calldata config) external;

    /// @notice Set the send() LayerZero messaging library version to version
    /// @param version New messaging library version
    function setSendVersion(uint16 version) external;

    /// @notice Set the lzReceive() LayerZero messaging library version to version
    /// @param version NMew messaging library version
    function setReceiveVersion(uint16 version) external;

    /// @notice Only when the UA needs to resume the message flow in blocking mode and clear the stored payload
    /// @param srcChainId The chainId of the source chain
    /// @param srcAddress The contract address of the source contract at the source chain
    function forceResumeReceive(uint16 srcChainId, bytes calldata srcAddress) external;
}
