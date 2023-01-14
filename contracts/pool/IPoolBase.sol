// SPDX-License-Identifier: UNLICENSED

import {IERC1155} from "@solidstate/contracts/interfaces/IERC1155.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";

pragma solidity ^0.8.0;

/**
 * @notice Base Pool interface, including ERC1155 functions
 */
interface IPoolBase is IERC1155, IERC1155Enumerable {
    /// @notice get token collection name
    /// @return collection name
    function name() external view returns (string memory);
}
