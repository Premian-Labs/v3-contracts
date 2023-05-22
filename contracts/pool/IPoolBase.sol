// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IERC1155Base} from "@solidstate/contracts/token/ERC1155/base/IERC1155Base.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";

interface IPoolBase is IERC1155Base, IERC1155Enumerable {
    error Pool__UseTransferPositionToTransferLPTokens();

    /// @notice get token collection name
    /// @return collection name
    function name() external view returns (string memory);
}
