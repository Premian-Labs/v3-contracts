// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {IERC1155Base} from "@solidstate/contracts/token/ERC1155/base/IERC1155Base.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";
import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

interface IPoolBase is IERC1155Base, IERC1155Enumerable, IMulticall {
    error Pool__UseTransferPositionToTransferLPTokens();

    /// @notice get token collection name
    /// @return collection name
    function name() external view returns (string memory);
}
