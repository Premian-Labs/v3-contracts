// SPDX-License-Identifier: UNLICENSED

import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";
import {ERC4626BaseStorage} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";
import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
contract UnderwriterVaultProxy is ProxyUpgradeableOwnable, ERC20MetadataInternal {
    
    constructor(
        address implementation,
        address base,
        address quote,
        string memory name,
        string memory symbol,
        bool isCall
    ) ProxyUpgradeableOwnable(implementation) {

        ERC4626BaseStorage.layout().asset = isCall ? base : quote;

        _setName(name);
        _setSymbol(symbol);
        _setDecimals(18);

        UnderwriterVaultStorage.layout().isCall = isCall;
        UnderwriterVaultStorage.layout().base = base;
        UnderwriterVaultStorage.layout().quote = quote;

        
    }

}