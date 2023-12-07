// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryDeployer} from "contracts/factory/PoolFactoryDeployer.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";

import {PoolBase} from "contracts/pool/PoolBase.sol";
import {PoolCore} from "contracts/pool/PoolCore.sol";
import {PoolDepositWithdraw} from "contracts/pool/PoolDepositWithdraw.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";

import {Premia} from "contracts/proxy/Premia.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {ERC20Router} from "contracts/router/ERC20Router.sol";
import {ReferralProxy} from "contracts/referral/ReferralProxy.sol";

import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";

import {OracleAdapterMock} from "contracts/test/adapter/OracleAdapterMock.sol";

import {ReferralMock} from "contracts/test/referral/ReferralMock.sol";
import {IReferralMock} from "contracts/test/referral/IReferralMock.sol";

import {ExchangeHelper} from "contracts/utils/ExchangeHelper.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {UserSettings} from "contracts/settings/UserSettings.sol";

import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";

import {UnderwriterVault} from "contracts/vault/strategies/underwriter/UnderwriterVault.sol";

import {VaultMiningProxy} from "contracts/mining/vaultMining/VaultMiningProxy.sol";
import {IVaultMining} from "contracts/mining/vaultMining/IVaultMining.sol";
import {VaultMining} from "contracts/mining/vaultMining/VaultMining.sol";

import {IVolatilityOracle} from "contracts/oracle/IVolatilityOracle.sol";
import {VolatilityOracle} from "contracts/oracle/VolatilityOracle.sol";

import {Base_Test} from "./Base.t.sol";

/// @dev Debugs deployed contracts with updated local implementations.
contract Debug_Test is Base_Test {
    // Test contracts
    IVolatilityOracle internal volatilityOracle;
    IVaultMining internal mining;

    // Variables
    string internal chain = "arbitrum";
    string internal path = string.concat("deployments/", chain, "/metadata.json");

    function isForkTest() internal virtual override returns (bool) {
        return true;
    }

    /// @dev Gets the network to fork.
    function getNetwork() internal virtual override returns (string memory) {
        return "arbitrum_one";
    }

    /// @dev Gets the starting block for the fork test.
    function getStartBlock() internal virtual override returns (uint256) {
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json, ".core[*].block");
        uint256[] memory blocks = abi.decode(data, (uint256[]));

        uint256 maxBlock = 0;
        for (uint256 i = 0; i < blocks.length; i++) {
            if (blocks[i] > maxBlock) maxBlock = blocks[i];
        }
        return maxBlock;
    }

    /// @dev Gets the start timestamp for the test.
    function getStartTimestamp() internal virtual override returns (uint256) {
        return block.timestamp;
    }

    /// @dev Gets the address associated with a given token.
    function getTokenAddress(string memory name) internal view returns (address) {
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json, string.concat(".tokens.", name));
        return abi.decode(data, (address));
    }

    /// @dev Gets the address for the deployed vault contract.
    function getVaultAddress(string memory name) internal view returns (address) {
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json, string.concat(".vaults.", name, ".address"));
        return abi.decode(data, (address));
    }

    /// @dev Gets the address for the deployed contract.
    function getAddress(string memory name) internal view returns (address) {
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json, string.concat(".core.", name, ".address"));
        return abi.decode(data, (address));
    }

    /// @dev Updates implementations for contracts on-chain.
    function deploy() internal virtual override {
        // Chainlink Oracle Adapter
        oracleAdapter = OracleAdapterMock(getAddress("ChainlinkAdapterProxy"));

        // Volatility Oracle
        VolatilityOracle volatilityOracleImpl = new VolatilityOracle();
        ProxyUpgradeableOwnable volatilityOracleProxy = ProxyUpgradeableOwnable(
            payable(getAddress("VolatilityOracleProxy"))
        );

        changePrank(volatilityOracleProxy.owner());
        volatilityOracleProxy.setImplementation(address(volatilityOracleImpl));

        volatilityOracle = IVolatilityOracle(address(volatilityOracleProxy));

        // Exchange Helper
        exchangeHelper = ExchangeHelper(getAddress("ExchangeHelper"));

        // Premia Diamond
        diamond = Premia(payable(getAddress("PremiaDiamond")));

        // Pool Factory
        PoolFactoryProxy factoryProxy = PoolFactoryProxy(payable(getAddress("PoolFactoryProxy")));

        PoolFactoryDeployer poolFactoryDeployer = new PoolFactoryDeployer(address(diamond), address(factoryProxy));
        PoolFactory factoryImpl = new PoolFactory(address(diamond), address(poolFactoryDeployer));

        changePrank(factoryProxy.owner());
        factoryProxy.setImplementation(address(factoryImpl));

        factory = PoolFactory(address(factoryProxy));

        // Router
        router = ERC20Router(getAddress("ERC20Router"));

        // Referral
        ReferralProxy referralProxy = ReferralProxy(payable(getAddress("ReferralProxy")));
        referral = IReferralMock(address(referralProxy));

        // User Settings
        UserSettings userSettingsImpl = new UserSettings();
        ProxyUpgradeableOwnable userSettingsProxy = ProxyUpgradeableOwnable(payable(getAddress("UserSettingsProxy")));

        changePrank(userSettingsProxy.owner());
        userSettingsProxy.setImplementation(address(userSettingsImpl));

        userSettings = IUserSettings(address(userSettingsProxy));

        // Vault Registry
        address vaultRegistryImpl = address(new VaultRegistry());
        ProxyUpgradeableOwnable vaultRegistryProxy = ProxyUpgradeableOwnable(payable(getAddress("VaultRegistryProxy")));

        changePrank(vaultRegistryProxy.owner());
        vaultRegistryProxy.setImplementation(vaultRegistryImpl);

        vaultRegistry = VaultRegistry(address(vaultRegistryProxy));

        // VxPremia
        VxPremia vxPremiaImpl = new VxPremia(
            address(0),
            address(0),
            address(premia),
            getTokenAddress("USDC"),
            address(exchangeHelper),
            address(vaultRegistry)
        );
        VxPremiaProxy vxPremiaProxy = VxPremiaProxy(payable(getAddress("VxPremiaProxy")));

        changePrank(vxPremiaProxy.owner());
        vxPremiaProxy.setImplementation(address(vxPremiaImpl));

        vxPremia = IVxPremia(address(vxPremiaProxy));

        // Vault Mining
        VaultMining miningImpl = new VaultMining(
            address(vaultRegistry),
            address(diamond),
            address(vxPremia),
            address(0)
        );
        VaultMiningProxy miningProxy = VaultMiningProxy(payable(getAddress("VaultMiningProxy")));

        changePrank(miningProxy.owner());
        miningProxy.setImplementation(address(miningImpl));
        mining = IVaultMining(address(miningProxy));

        // Pool Diamond
        PoolBase poolBaseImpl = new PoolBase();

        PoolCore poolCoreImpl = new PoolCore(
            address(factory),
            address(router),
            getTokenAddress("WETH"),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        PoolDepositWithdraw poolDepositWithdrawImpl = new PoolDepositWithdraw(
            address(factory),
            address(router),
            getTokenAddress("WETH"),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        PoolTrade poolTradeImpl = new PoolTrade(
            address(factory),
            address(router),
            getTokenAddress("WETH"),
            FEE_RECEIVER,
            address(referral),
            address(userSettings),
            address(vaultRegistry),
            address(vxPremia)
        );

        /////////////////////
        // Register facets //
        /////////////////////

        // PoolBase
        poolBaseSelectors.push(poolBaseImpl.accountsByToken.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOf.selector);
        poolBaseSelectors.push(poolBaseImpl.balanceOfBatch.selector);
        poolBaseSelectors.push(poolBaseImpl.isApprovedForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.name.selector);
        poolBaseSelectors.push(poolBaseImpl.safeBatchTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.safeTransferFrom.selector);
        poolBaseSelectors.push(poolBaseImpl.setApprovalForAll.selector);
        poolBaseSelectors.push(poolBaseImpl.tokensByAccount.selector);
        poolBaseSelectors.push(poolBaseImpl.totalHolders.selector);
        poolBaseSelectors.push(poolBaseImpl.totalSupply.selector);

        // PoolCore
        poolCoreSelectors.push(poolCoreImpl.annihilate.selector);
        poolCoreSelectors.push(poolCoreImpl.annihilateFor.selector);
        poolCoreSelectors.push(poolCoreImpl.claim.selector);
        poolCoreSelectors.push(poolCoreImpl.exercise.selector);
        poolCoreSelectors.push(poolCoreImpl.exerciseFor.selector);
        poolCoreSelectors.push(poolCoreImpl.getClaimableFees.selector);
        poolCoreSelectors.push(poolCoreImpl.getPoolSettings.selector);
        poolCoreSelectors.push(poolCoreImpl.getSettlementPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.getTokenIds.selector);
        poolCoreSelectors.push(poolCoreImpl.marketPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.settle.selector);
        poolCoreSelectors.push(poolCoreImpl.settleFor.selector);
        poolCoreSelectors.push(poolCoreImpl.settlePosition.selector);
        poolCoreSelectors.push(poolCoreImpl.settlePositionFor.selector);
        poolCoreSelectors.push(poolCoreImpl.takerFee.selector);
        poolCoreSelectors.push(poolCoreImpl._takerFeeLowLevel.selector);
        poolCoreSelectors.push(poolCoreImpl.transferPosition.selector);
        poolCoreSelectors.push(poolCoreImpl.tryCacheSettlementPrice.selector);
        poolCoreSelectors.push(poolCoreImpl.writeFrom.selector);
        poolCoreSelectors.push(poolCoreImpl.ticks.selector);

        // PoolDepositWithdraw
        poolDepositWithdrawSelectors.push(
            bytes4(
                keccak256("deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256)")
            )
        );
        poolDepositWithdrawSelectors.push(
            bytes4(
                keccak256(
                    "deposit((address,address,uint256,uint256,uint8),uint256,uint256,uint256,uint256,uint256,bool)"
                )
            )
        );
        poolDepositWithdrawSelectors.push(poolDepositWithdrawImpl.withdraw.selector);
        poolDepositWithdrawSelectors.push(poolDepositWithdrawImpl.getNearestTicksBelow.selector);

        // PoolTrade
        poolTradeSelectors.push(poolTradeImpl.cancelQuotesOB.selector);
        poolTradeSelectors.push(poolTradeImpl.fillQuoteOB.selector);
        poolTradeSelectors.push(poolTradeImpl.flashLoan.selector);
        poolTradeSelectors.push(poolTradeImpl.maxFlashLoan.selector);
        poolTradeSelectors.push(poolTradeImpl.flashFee.selector);
        poolTradeSelectors.push(poolTradeImpl.getQuoteAMM.selector);
        poolTradeSelectors.push(poolTradeImpl.getQuoteOBFilledAmount.selector);
        poolTradeSelectors.push(poolTradeImpl.trade.selector);

        IDiamondWritableInternal.FacetCut[] memory facetCuts = new IDiamondWritableInternal.FacetCut[](4);

        facetCuts[0] = IDiamondWritableInternal.FacetCut(
            address(poolBaseImpl),
            IDiamondWritableInternal.FacetCutAction.REPLACE,
            poolBaseSelectors
        );

        facetCuts[1] = IDiamondWritableInternal.FacetCut(
            address(poolCoreImpl),
            IDiamondWritableInternal.FacetCutAction.REPLACE,
            poolCoreSelectors
        );

        facetCuts[2] = IDiamondWritableInternal.FacetCut(
            address(poolDepositWithdrawImpl),
            IDiamondWritableInternal.FacetCutAction.REPLACE,
            poolDepositWithdrawSelectors
        );

        facetCuts[3] = IDiamondWritableInternal.FacetCut(
            address(poolTradeImpl),
            IDiamondWritableInternal.FacetCutAction.REPLACE,
            poolTradeSelectors
        );

        changePrank(diamond.owner());
        diamond.diamondCut(facetCuts, address(0), "");

        // Update underwriter vault implementation
        bytes32 vaultType = keccak256("UnderwriterVault");
        UnderwriterVault vaultImpl = new UnderwriterVault(
            address(vaultRegistry),
            FEE_RECEIVER,
            address(volatilityOracle),
            address(factory),
            address(router),
            address(vxPremia),
            address(diamond),
            address(mining)
        );
        vaultRegistry.setImplementation(vaultType, address(vaultImpl));

        // Label Contracts
        vm.label({account: address(oracleAdapter), newLabel: "ChainlinkAdapter"});
        vm.label({account: address(volatilityOracle), newLabel: "VolatilityOracle"});
        vm.label({account: address(exchangeHelper), newLabel: "ExchangeHelper"});
        vm.label({account: address(diamond), newLabel: "Premia"});
        vm.label({account: address(factory), newLabel: "PoolFactory"});
        vm.label({account: address(router), newLabel: "Router"});
        vm.label({account: address(referral), newLabel: "Referral"});
        vm.label({account: address(userSettings), newLabel: "UserSettings"});
        vm.label({account: address(vaultRegistry), newLabel: "VaultRegistry"});
        vm.label({account: address(vxPremia), newLabel: "VxPremia"});
        vm.label({account: address(mining), newLabel: "VaultMining"});
    }

    function test_debug_system() public {
        // Enter code for debugging here, e.g. (remove skip)
        // address vaultAddr = getVaultAddress("pSV-WETH/USDCe-C");
        // IVault vault = IVault(vaultAddr);
        // uint256 totalAssets = vault.totalAssets();
        // emit log_named_uint("Total Assets", totalAssets);
    }
}
