// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "../../factory/IPoolFactory.sol";
import {Vault} from "../../vault/Vault.sol";

contract VaultMock is Vault {
    constructor(address vaultMining) Vault(vaultMining) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function _totalAssets() internal view override returns (uint256) {
        return _totalSupply();
    }

    function updateSettings(bytes memory settings) external {}

    function getSettings() external pure returns (bytes memory) {
        return "";
    }

    function getQuote(IPoolFactory.PoolKey calldata, UD60x18, bool, address) external pure returns (uint256 premium) {
        return 0;
    }

    function trade(IPoolFactory.PoolKey calldata poolKey, UD60x18, bool, uint256, address) external {}
}
