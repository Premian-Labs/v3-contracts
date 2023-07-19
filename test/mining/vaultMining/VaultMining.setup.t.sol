// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {Test} from "forge-std/Test.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {VaultMining} from "contracts/mining/vaultMining/VaultMining.sol";
import {VaultMiningProxy} from "contracts/mining/vaultMining/VaultMiningProxy.sol";
import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";
import {VxPremiaStorage} from "contracts/staking/VxPremiaStorage.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {IVaultRegistry} from "contracts/vault/IVaultRegistry.sol";
import {VaultMock} from "contracts/test/vault/VaultMock.sol";
import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";
import {OptionRewardMock} from "../../../contracts/test/mining/optionReward/OptionRewardMock.sol";

import {Assertions} from "../../Assertions.sol";

contract ProxyManagerMock {
    function getPoolList() external pure returns (address[] memory poolList) {
        return poolList;
    }
}

contract VaultMiningSetup is Test, Assertions {
    uint256 internal constant ONE_DAY = 24 * 3600;

    address internal admin;
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
    VaultMock internal vaultD;
    VaultMock internal vaultNotRegistered;

    function setUp() public virtual {
        admin = vm.addr(1);
        alice = vm.addr(2);
        bob = vm.addr(3);
        carol = vm.addr(4);

        vm.startPrank(admin);

        address vaultRegistryImpl = address(new VaultRegistry());
        address vaultRegistryProxy = address(new ProxyUpgradeableOwnable(vaultRegistryImpl));
        vaultRegistry = VaultRegistry(vaultRegistryProxy);

        premia = new ERC20Mock("PREMIA", 18);
        address usdc = address(new ERC20Mock("USDC", 6));

        address proxyManager = address(new ProxyManagerMock());

        address vxPremiaImpl = address(
            new VxPremia(proxyManager, address(0), address(premia), usdc, address(0), vaultRegistryProxy)
        );
        address vxPremiaProxy = address(new VxPremiaProxy(address(vxPremiaImpl)));
        vxPremia = VxPremia(address(vxPremiaProxy));

        optionReward = new OptionRewardMock(address(premia));

        address vaultMiningImpl = address(
            new VaultMining(address(vaultRegistry), address(premia), address(vxPremia), address(optionReward))
        );
        address vaultMiningProxy = address(new VaultMiningProxy(address(vaultMiningImpl), ud(365 * 1000e18)));
        vaultMining = VaultMining(vaultMiningProxy);

        premia.mint(admin, 500_000e18);
        premia.approve(address(vaultMining), 500_000e18);
        vaultMining.addRewards(ud(200_000e18));
        premia.approve(address(vxPremia), 500_000e18);
        vxPremia.stake(100_000e18, uint64(ONE_DAY * 365 * 4));

        vaultA = new VaultMock(address(vaultMining));
        vaultB = new VaultMock(address(vaultMining));
        vaultC = new VaultMock(address(vaultMining));
        vaultD = new VaultMock(address(vaultMining));
        vaultNotRegistered = new VaultMock(address(vaultMining));

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
        vaultRegistry.addVault(
            address(vaultD),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](4);
        votes[0] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultA))
        });
        votes[1] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultB))
        });
        votes[2] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultC))
        });
        votes[3] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultD))
        });
        vxPremia.castVotes(votes);

        vaultMining.updateVault(address(vaultA));
        vaultMining.updateVault(address(vaultB));
        vaultMining.updateVault(address(vaultC));
        vaultMining.updateVault(address(vaultD));

        vm.stopPrank();
    }
}
