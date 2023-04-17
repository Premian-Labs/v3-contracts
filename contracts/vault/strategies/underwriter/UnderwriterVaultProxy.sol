// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {ERC4626BaseStorage} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";

import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVaultRegistry} from "../../IVaultRegistry.sol";

contract UnderwriterVaultProxy is Proxy {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;

    // Constants
    bytes32 public constant VAULT_TYPE = keccak256("UnderwriterVault");

    address internal immutable VAULT_REGISTRY;

    // Errors
    error VaultProxy__CLevelBounds();

    constructor(
        address vaultRegistry,
        address base,
        address quote,
        address oracleAdapter,
        string memory name,
        string memory symbol,
        bool isCall
    ) {
        VAULT_REGISTRY = vaultRegistry;

        ERC20MetadataStorage.Layout storage metadata = ERC20MetadataStorage
            .layout();
        metadata.name = name;
        metadata.symbol = symbol;
        metadata.decimals = 18;

        ERC4626BaseStorage.layout().asset = isCall ? base : quote;

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        bytes memory settings = IVaultRegistry(VAULT_REGISTRY).getSettings(
            VAULT_TYPE
        );
        l.updateSettings(settings);

        l.isCall = isCall;
        l.base = base;
        l.quote = quote;

        uint8 baseDecimals = IERC20Metadata(base).decimals();
        uint8 quoteDecimals = IERC20Metadata(quote).decimals();
        l.baseDecimals = baseDecimals;
        l.quoteDecimals = quoteDecimals;

        l.lastTradeTimestamp = block.timestamp;
        l.oracleAdapter = oracleAdapter;
    }

    /// @inheritdoc Proxy
    function _getImplementation()
        internal
        view
        virtual
        override
        returns (address)
    {
        return IVaultRegistry(VAULT_REGISTRY).getImplementation(VAULT_TYPE);
    }

    /// @notice get address of implementation contract
    /// @return implementation address
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}
