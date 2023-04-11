// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";
import {ERC4626BaseStorage} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";

import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {ZERO} from "../../../libraries/Constants.sol";
import {ProxyUpgradeableOwnable} from "../../../proxy/ProxyUpgradeableOwnable.sol";

contract UnderwriterVaultProxy is
    ProxyUpgradeableOwnable,
    ERC20MetadataInternal
{
    // Errors
    error VaultProxy__CLevelBounds();

    struct CLevel {
        // The minimum C-level allowed by the C-level mechanism
        UD60x18 minCLevel;
        // The maximum C-level allowed by the C-level mechanism
        UD60x18 maxCLevel;
        // The curvature parameter
        UD60x18 alphaCLevel;
        // The decay rate of the C-level back down to ordinary level
        UD60x18 hourlyDecayDiscount;
    }

    struct TradeBounds {
        // The maximum time until maturity the vault will underwrite
        UD60x18 maxDTE;
        // The minimum time until maturity the vault will underwrite
        UD60x18 minDTE;
        // The maximum delta the vault will underwrite
        SD59x18 minDelta;
        // The minimum delta the vault will underwrite
        SD59x18 maxDelta;
    }

    constructor(
        address implementation,
        address base,
        address quote,
        address oracleAdapter,
        string memory name,
        string memory symbol,
        bool isCall,
        CLevel memory cLevel,
        TradeBounds memory tradeBounds
    ) ProxyUpgradeableOwnable(implementation) {
        ERC4626BaseStorage.layout().asset = isCall ? base : quote;

        _setName(name);
        _setSymbol(symbol);
        _setDecimals(18);

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (cLevel.maxCLevel == ZERO) revert VaultProxy__CLevelBounds();
        if (cLevel.alphaCLevel == ZERO) revert VaultProxy__CLevelBounds();

        l.isCall = isCall;
        l.base = base;
        l.quote = quote;

        uint8 baseDecimals = IERC20Metadata(base).decimals();
        uint8 quoteDecimals = IERC20Metadata(quote).decimals();

        l.baseDecimals = baseDecimals;
        l.quoteDecimals = quoteDecimals;

        l.maxDTE = tradeBounds.maxDTE;
        l.minDTE = tradeBounds.minDTE;
        l.minDelta = tradeBounds.minDelta;
        l.maxDelta = tradeBounds.maxDelta;
        l.minCLevel = cLevel.minCLevel;
        l.maxCLevel = cLevel.maxCLevel;
        l.alphaCLevel = cLevel.alphaCLevel;
        l.hourlyDecayDiscount = cLevel.hourlyDecayDiscount;
        l.lastTradeTimestamp = block.timestamp;
        l.oracleAdapter = oracleAdapter;
    }
}
