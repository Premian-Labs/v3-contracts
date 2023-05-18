// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {OracleAdapterMock} from "contracts/test/adapter/OracleAdapterMock.sol";
import {VolatilityOracleMock} from "contracts/test/oracle/VolatilityOracleMock.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {DeployTest} from "../../../Deploy.t.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";
import {UnderwriterVaultProxy} from "contracts/vault/strategies/underwriter/UnderwriterVaultProxy.sol";

contract UnderwriterVaultDeployTest is DeployTest {
    bytes32 vaultType;

    address longCall;
    address shortCall;

    VolatilityOracleMock volOracle;
    VaultRegistry vaultRegistry;

    UnderwriterVaultMock callVault;
    UnderwriterVaultMock putVault;

    function setUp() public virtual override {
        super.setUp();

        longCall = address(new ERC20Mock("LONG_CALL", 18));
        shortCall = address(new ERC20Mock("SHORT_CALL", 18));

        address[5] memory users = [
            users.caller,
            users.receiver,
            users.underwriter,
            users.lp,
            users.trader
        ];

        for (uint256 i; i < users.length; i++) {
            deal(base, users[i], 1_000e18);
            deal(quote, users[i], 1_000_000e6);
        }

        oracleAdapter.setQuote(ud(1500e18));

        volOracle = new VolatilityOracleMock();

        poolKey.strike = ud(1500e18);
        poolKey.maturity = 1677225600;

        // Vault vaultRegistry
        address vaultRegistryImpl = address(new VaultRegistry());
        address vaultRegistryProxy = address(
            new ProxyUpgradeableOwnable(vaultRegistryImpl)
        );

        vaultRegistry = VaultRegistry(vaultRegistryProxy);
        vaultType = keccak256("UnderwriterVault");

        // Update settings
        uint256[] memory settings = new uint256[](10);

        settings[0] = 3e18;
        settings[1] = 0.005e18;
        settings[2] = 1e18;
        settings[3] = 1.2e18;
        settings[4] = 3e18;
        settings[5] = 30e18;
        settings[6] = 0.1e18;
        settings[7] = 0.7e18;
        settings[8] = 0.05e18;
        settings[9] = 0.02e18;

        vaultRegistry.updateSettings(vaultType, abi.encode(settings));

        // Deploy and set vault implementation
        address vaultImpl = address(
            new UnderwriterVaultMock(
                vaultRegistryProxy,
                feeReceiver,
                address(volOracle),
                address(factory),
                address(router)
            )
        );

        vaultRegistry.setImplementation(vaultType, vaultImpl);

        // Deploy vaults
        address callVaultProxy = address(
            new UnderwriterVaultProxy(
                vaultRegistryProxy,
                base,
                quote,
                address(oracleAdapter),
                "WETH Vault",
                "WETHVault",
                true
            )
        );

        callVault = UnderwriterVaultMock(callVaultProxy);

        address putVaultProxy = address(
            new UnderwriterVaultProxy(
                vaultRegistryProxy,
                base,
                quote,
                address(oracleAdapter),
                "WETH Vault",
                "WETHVault",
                false
            )
        );

        callVault = UnderwriterVaultMock(putVaultProxy);
    }
}
