// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";

/// @dev Interface of the IOFT core standard
interface IOFTCore is IERC165 {
    /// @dev Estimate send token `tokenId` to (`dstChainId`, `toAddress`)
    /// @param dstChainId L0 defined chain id to send tokens too
    /// @param toAddress Dynamic bytes array which contains the address to whom you are sending tokens to on the dstChain
    /// @param amount Amount of the tokens to transfer
    /// @param useZro Indicates to use zro to pay L0 fees
    /// @param adapterParams Flexible bytes array to indicate messaging adapter services in L0
    function estimateSendFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        bool useZro,
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    /// @dev Send `amount` amount of token to (`dstChainId`, `toAddress`) from `from`
    /// @param from The owner of token
    /// @param dstChainId The destination chain identifier
    /// @param toAddress Can be any size depending on the `dstChainId`.
    /// @param amount The quantity of tokens in wei
    /// @param refundAddress The address LayerZero refunds if too much message fee is sent
    /// @param zroPaymentAddress Set to address(0x0) if not paying in ZRO (LayerZero Token)
    /// @param adapterParams Flexible bytes array to indicate messaging adapter services
    function sendFrom(
        address from,
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external payable;

    /// @dev Returns the circulating amount of tokens on current chain
    function circulatingSupply() external view returns (uint256);

    /// @dev Emitted when `amount` tokens are moved from the `sender` to (`dstChainId`, `toAddress`)
    event SendToChain(address indexed sender, uint16 indexed dstChainId, bytes indexed toAddress, uint256 amount);

    /// @dev Emitted when `amount` tokens are received from `srcChainId` into the `toAddress` on the local chain.
    event ReceiveFromChain(
        uint16 indexed srcChainId,
        bytes indexed srcAddress,
        address indexed toAddress,
        uint256 amount
    );

    event SetUseCustomAdapterParams(bool _useCustomAdapterParams);
}
