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
        uint256 minClevel;
        uint256 maxClevel;
        uint256 alphaClevel;
        uint256 hourlyDecayDiscount;
    }

    struct TradeBounds {
        uint256 maxDTE;
        uint256 minDTE;
        int256 minDelta;
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

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultProxy
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
