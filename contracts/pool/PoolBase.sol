// SPDX-License-Identifier: UNLICENSED



// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ERC165} from "@solidstate/contracts/introspection/ERC165.sol";
import {ERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {IPoolBase} from "./IPoolBase.sol";

contract PoolBase is IPoolBase, ERC1155Enumerable, ERC165, Multicall {
    /**
     * @inheritdoc IPoolBase
     */
    function name() external view returns (string memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // ToDo : Differentiate name if a pool already exists with other oracles for this pair ?

        return
            string(
                abi.encodePacked(
                    IERC20Metadata(l.underlying).symbol(),
                    " / ",
                    IERC20Metadata(l.base).symbol(),
                    " - Premia Options Pool"
                )
            );
    }
}
