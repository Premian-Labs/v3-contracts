// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {SolidStateERC4626} from "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";

import {ONE} from "../libraries/Constants.sol";
import {IVaultMining} from "../mining/IVaultMining.sol";
import {IVault} from "./IVault.sol";

abstract contract Vault is IVault, SolidStateERC4626 {
    address internal immutable VAULT_MINING;

    constructor(address vaultMining) {
        VAULT_MINING = vaultMining;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (from == to) return;

        uint256 newTotalShares = _totalSupply();
        uint256 newFromShares = _balanceOf(from);
        uint256 newToShares = _balanceOf(to);

        if (from == address(0)) newTotalShares += amount;
        if (to == address(0)) newTotalShares -= amount;

        UD60x18 utilisation = getUtilisation();

        if (from != address(0)) {
            newFromShares -= amount;
            IVaultMining(VAULT_MINING).updateUser(
                from,
                address(this),
                ud(newFromShares),
                ud(newTotalShares),
                utilisation
            );
        }

        if (to != address(0)) {
            newToShares += amount;
            IVaultMining(VAULT_MINING).updateUser(to, address(this), ud(newToShares), ud(newTotalShares), utilisation);
        }
    }

    function getUtilisation() public view virtual returns (UD60x18) {
        return ONE;
    }
}
