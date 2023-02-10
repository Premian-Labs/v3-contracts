// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title The interface for an oracle that provides price quotes
 * @notice These methods allow users to add support for pairs, and then ask for quotes
 * @notice derived from https://github.com/Mean-Finance/oracles
 */
interface ITokenPriceOracle is IERC165 {
    /// @notice Thrown when trying to add pair where base and quote are the same
    error Oracle__BaseAndQuoteAreSame(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that has already been added
    error Oracle__PairAlreadySupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that cannot be supported
    error Oracle__PairCannotBeSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to execute a quote with a pair that isn't supported yet
    error Oracle__PairNotSupportedYet(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error Oracle__ZeroAddress();

    /**
     * @notice Returns whether this oracle can support the given pair of tokens
     * @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
     * @param tokenA One of the pair's tokens
     * @param tokenB The other of the pair's tokens
     * @return Whether the given pair of tokens can be supported by the oracle
     */
    function canSupportPair(
        address tokenA,
        address tokenB
    ) external view returns (bool);

    /**
     * @notice Returns whether this oracle is already supporting the given pair of tokens
     * @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
     * @param tokenA One of the pair's tokens
     * @param tokenB The other of the pair's tokens
     * @return Whether the given pair of tokens is already being supported by the oracle
     */
    function isPairAlreadySupported(
        address tokenA,
        address tokenB
    ) external view returns (bool);

    /**
     * @notice Returns a quote, based on the given token pair
     * @dev Will revert if pair isn't supported
     * @param tokenIn The token that will be provided
     * @param tokenOut The token we would like to quote
     * @param data Custom data that the oracle might need to operate
     * @return amountOut How much `tokenOut` will be returned in exchange for `amountIn` amount of `tokenIn`
     */
    function quote(
        address tokenIn,
        address tokenOut,
        bytes calldata data
    ) external view returns (uint256 amountOut);

    /**
     * @notice Add or reconfigures the support for a given pair. This function will let the oracle take some actions
     *         to configure the pair, in preparation for future quotes. Can be called many times in order to let the oracle
     *         re-configure for a new context
     * @dev Will revert if pair cannot be supported. tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
     * @param tokenA One of the pair's tokens
     * @param tokenB The other of the pair's tokens
     * @param data Custom data that the oracle might need to operate
     */
    function addOrModifySupportForPair(
        address tokenA,
        address tokenB,
        bytes calldata data
    ) external;

    /**
     * @notice Adds support for a given pair if the oracle didn't support it already. If called for a pair that is already supported,
     *         then nothing will happen. This function will let the oracle take some actions to configure the pair, in preparation
     *         for future quotes
     * @dev Will revert if pair cannot be supported. tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
     * @param tokenA One of the pair's tokens
     * @param tokenB The other of the pair's tokens
     * @param data Custom data that the oracle might need to operate
     */
    function addSupportForPairIfNeeded(
        address tokenA,
        address tokenB,
        bytes calldata data
    ) external;

    /**
     * @notice Returns true if this contract implements the interface defined by `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section] to learn more about how these ids are
     * created.
     * @dev This function call must use less than 30 000 gas.
     * @param interfaceId The interface identifier
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
