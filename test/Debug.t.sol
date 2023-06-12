// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {IPool} from "contracts/pool/IPool.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {Premia} from "contracts/proxy/Premia.sol";

import "forge-std/Test.sol";
import {Referral} from "contracts/referral/Referral.sol";
import {ReferralProxy} from "contracts/referral/ReferralProxy.sol";
import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {IPoolTrade} from "contracts/pool/IPoolTrade.sol";

contract Debug is Test {
    function test_debug_trade() public {
        string memory RPC_URL = string.concat("https://arb-goerli.g.alchemy.com/v2/", vm.envString("API_KEY_ALCHEMY"));
        uint256 fork = vm.createFork(RPC_URL, 25474288);
        vm.selectFork(fork);

        address poolTrade = address(
            new PoolTrade(
                0x78438a37Ab82d757657e47E15d28646843FAaeDD,
                0xC42f597D6b05033199aa5aB8A953C572ab63072a,
                0x7F5bc2250ea57d8ca932898297b1FF9aE1a04999,
                0x0e2fF9cbb1b0866b9988311C4d55BbC3e584bb54,
                0x1f6A482AD83D0fb990897FCea83C226312109D0B,
                0x6A1bec4D03A7e2CBDb5AD4a151065dC9e9A8076E,
                0x80196c9D4094B36f3e142C80C4Fd12247f79ef2D,
                0xe416d620436F77e4F4867b67E269A08972067808
            )
        );

        IDiamondWritableInternal.FacetCut[] memory facetCuts = new IDiamondWritableInternal.FacetCut[](1);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IPoolTrade.trade.selector;

        facetCuts[0] = IDiamondWritableInternal.FacetCut(
            address(poolTrade),
            IDiamondWritableInternal.FacetCutAction.REPLACE,
            selectors
        );

        vm.prank(0x0e2fF9cbb1b0866b9988311C4d55BbC3e584bb54);
        Premia(payable(0xCFb3000bD2Ac6FdaFb4c77C43F603c3ae14De308)).diamondCut(facetCuts, address(0), "");

        address referral = address(new Referral(0x78438a37Ab82d757657e47E15d28646843FAaeDD));

        vm.prank(0x0e2fF9cbb1b0866b9988311C4d55BbC3e584bb54);
        ReferralProxy(payable(0x1f6A482AD83D0fb990897FCea83C226312109D0B)).setImplementation(referral);

        vm.startPrank(0xA28eBeb2d86f349d974BAA5b631ee64a71c4c220);

        IPool(0x51509B559ce5E83CCd579985eC846617e76D0797).trade(
            ud(500000000000000000),
            true,
            78646633752380059,
            0x589155f2F38B877D7Ac3C1AcAa2E42Ec8a9bb709
        );
    }

    fallback() external payable {}
}
