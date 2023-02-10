// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {ITokenPriceOracle} from "./ITokenPriceOracle.sol";

/// @title A base implementation of `ITokenPriceOracle` that implements `ERC165` and `Multicall`
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract BaseOracle is Multicall, ERC165, ITokenPriceOracle {
    /// @inheritdoc ITokenPriceOracle
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ITokenPriceOracle, ERC165) returns (bool) {
        return
            _interfaceId == type(ITokenPriceOracle).interfaceId ||
            _interfaceId == type(Multicall).interfaceId ||
            super.supportsInterface(_interfaceId);
    }
}
