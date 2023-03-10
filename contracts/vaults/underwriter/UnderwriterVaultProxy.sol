// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";
import {ERC4626BaseStorage} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";
import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";

contract UnderwriterVaultProxy is
    ProxyUpgradeableOwnable,
    ERC20MetadataInternal
{
    struct Clevel {
        // The minimum C-levelm allowed by the C-level mechanism
        uint256 minClevel;
        // The maximum C-levelm allowed by the C-level mechanism
        uint256 maxClevel;
        // (fill in with better description)
        uint256 alphaClevel;
        // The decay rate of the C-level back down to ordinary level
        uint256 hourlyDecayDiscount;
    }

    struct TradeBounds {
        // The maximum time until maturity the vault will underwrite
        uint256 maxDTE;
        // The minimum time until maturity the vault will underwrite
        uint256 minDTE;
        // The maximum delta the vault will underwrite
        int256 minDelta;
        // The minimum delta the vault will underwrite
        int256 maxDelta;
    }

    constructor(
        address implementation,
        address base,
        address quote,
        address oracleAdapter,
        string memory name,
        string memory symbol,
        bool isCall,
        Clevel memory cLevel,
        TradeBounds memory tradeBounds,
        uint256 lastTradeTimestamp
    ) ProxyUpgradeableOwnable(implementation) {
        ERC4626BaseStorage.layout().asset = isCall ? base : quote;

        _setName(name);
        _setSymbol(symbol);
        _setDecimals(18);

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        l.isCall = isCall;
        l.base = base;
        l.quote = quote;
        l.maxDTE = tradeBounds.maxDTE;
        l.minDTE = tradeBounds.minDTE;
        l.minDelta = tradeBounds.minDelta;
        l.maxDelta = tradeBounds.maxDelta;
        l.minCLevel = cLevel.minClevel;
        l.maxCLevel = cLevel.maxClevel;
        l.alphaCLevel = cLevel.alphaClevel;
        l.hourlyDecayDiscount = cLevel.hourlyDecayDiscount;
        l.lastTradeTimestamp = lastTradeTimestamp;
        l.oracleAdapter = oracleAdapter;
    }
}
