// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {IVaultMining} from "contracts/mining/IVaultMining.sol";
import {VaultMining} from "contracts/mining/VaultMining.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {IVaultRegistry} from "contracts/vault/IVaultRegistry.sol";
import {VaultMock} from "contracts/test/vault/VaultMock.sol";
import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";
import {OptionRewardMock} from "contracts/test/mining/OptionRewardMock.sol";

import {DebugUtils} from "../DebugUtils.sol";

contract VaultMiningTest is Test {
    address internal alice;
    address internal bob;
    address internal carol;

    VaultRegistry internal vaultRegistry;
    VaultMining internal vaultMining;
    ERC20Mock internal premia;
    VxPremia internal vxPremia;
    OptionRewardMock internal optionReward;

    VaultMock internal vaultA;
    VaultMock internal vaultB;
    VaultMock internal vaultC;

    function setUp() public {
        alice = vm.addr(1);
        bob = vm.addr(2);
        carol = vm.addr(3);

        address vaultRegistryImpl = address(new VaultRegistry());
        address vaultRegistryProxy = address(new ProxyUpgradeableOwnable(vaultRegistryImpl));
        vaultRegistry = VaultRegistry(vaultRegistryProxy);

        premia = new ERC20Mock("PREMIA", 18);
        address usdc = address(new ERC20Mock("USDC", 6));

        address vxPremiaImpl = address(
            new VxPremia(address(0), address(0), address(premia), usdc, address(0), vaultRegistryProxy)
        );
        address vxPremiaProxy = address(new VxPremiaProxy(address(vxPremiaImpl)));
        vxPremia = VxPremia(address(vxPremiaProxy));

        optionReward = new OptionRewardMock(address(premia));

        address vaultMiningImpl = address(
            new VaultMining(address(vaultRegistry), address(premia), address(vxPremia), address(optionReward))
        );
        address vaultMiningProxy = address(new ProxyUpgradeableOwnable(address(vaultMiningImpl)));
        vaultMining = VaultMining(vaultMiningProxy);

        vaultA = new VaultMock(address(vaultMining));
        vaultB = new VaultMock(address(vaultMining));
        vaultC = new VaultMock(address(vaultMining));

        vaultRegistry.addVault(
            address(vaultA),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        vaultRegistry.addVault(
            address(vaultB),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        vaultRegistry.addVault(
            address(vaultC),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );
    }

    function test_vaultMining() public {
        console2.log(DebugUtils.formatNumber(vaultMining.getVaultInfo(address(vaultA)).totalShares));
        vaultA.mint(alice, 1000 ether);
        console2.log(DebugUtils.formatNumber(vaultMining.getVaultInfo(address(vaultA)).totalShares));
        vaultA.mint(bob, 500 ether);
        console2.log(DebugUtils.formatNumber(vaultMining.getVaultInfo(address(vaultA)).totalShares));
        vaultA.mint(carol, 100 ether);

        IVaultMining.VaultInfo memory vInfo = vaultMining.getVaultInfo(address(vaultA));
        console2.log(DebugUtils.formatNumber(vInfo.totalShares));
        console2.log(vInfo.lastRewardTimestamp);

        assertTrue(true);
    }
}
