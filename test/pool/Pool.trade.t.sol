// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {IPoolTrade} from "contracts/pool/IPoolTrade.sol";
import {Premia} from "contracts/proxy/Premia.sol";
import {Referral} from "contracts/referral/Referral.sol";
import {ReferralProxy} from "contracts/referral/ReferralProxy.sol";
import {IPool} from "contracts/pool/IPool.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTradeTest is DeployTest {
    function test_trade_Buy500Options_WithApproval() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, true);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);

        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(tradeSize, true, totalPremium + totalPremium / 10, address(0));

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_trade_Buy500Options_WithReferral() public {
        posKey.orderType = Position.OrderType.CS;
        uint256 initialCollateral = deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        (uint256 totalPremium, uint256 takerFee) = pool.getQuoteAMM(users.trader, tradeSize, true);

        uint256 totalRebate;

        {
            (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(takerFee);

            UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(takerFee);

            uint256 primaryRebate = scaleDecimals(_primaryRebate);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate);

            totalRebate = primaryRebate + secondaryRebate;
        }

        address token = getPoolToken();

        vm.startPrank(users.trader);

        deal(token, users.trader, totalPremium);
        IERC20(token).approve(address(router), totalPremium);

        pool.trade(tradeSize, true, totalPremium + totalPremium / 10, users.referrer);

        vm.stopPrank();

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);

        assertEq(IERC20(token).balanceOf(users.trader), 0);
        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);

        assertEq(IERC20(token).balanceOf(address(pool)), initialCollateral + totalPremium - totalRebate);
    }

    function test_trade_HandleRoundingErrors_WithReferral() public {
        // This test is ensuring a fix related to rounded errors in referral contract we encountered on testnet during
        // testing is solves
        // We cant reproduce the exact same scenario easily by reproducing steps leading to this, because of some other
        // upgrades made
        // This test will probably need to be removed at some point as it will fail once Goerli is deprecated
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

    function test_trade_Sell500Options_WithApproval() public {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = scaleDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10, address(0));

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_trade_Sell500Options_WithReferral() public {
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        uint256 initialCollateral;

        {
            UD60x18 _collateral = contractsToCollateral(UD60x18.wrap(depositSize));

            initialCollateral = scaleDecimals(_collateral * posKey.lower.avg(posKey.upper));
        }

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        uint256 collateral = scaleDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, uint256 takerFee) = pool.getQuoteAMM(users.trader, tradeSize, false);

        uint256 totalRebate;

        {
            (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(takerFee);

            UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(takerFee);

            uint256 primaryRebate = scaleDecimals(_primaryRebate);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate);

            totalRebate = primaryRebate + secondaryRebate;
        }

        address token = getPoolToken();

        vm.startPrank(users.trader);

        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10, users.referrer);

        vm.stopPrank();

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);

        assertEq(IERC20(token).balanceOf(users.trader), totalPremium);
        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);

        assertEq(IERC20(token).balanceOf(address(pool)), initialCollateral + collateral - totalPremium - totalRebate);
    }

    function test_trade_RevertIf_BuyOptions_WithTotalPremiumAboveLimit() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, true);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, totalPremium, 0, totalPremium - 1)
        );
        pool.trade(tradeSize, true, totalPremium - 1, address(0));
    }

    function test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit() public {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = scaleDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                totalPremium,
                totalPremium + 1,
                type(uint256).max
            )
        );
        pool.trade(tradeSize, false, totalPremium + 1, address(0));
    }

    function test_trade_RevertIf_BuyOptions_WithInsufficientAskLiquidity() public {
        posKey.orderType = Position.OrderType.CS;
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientAskLiquidity.selector);
        pool.trade(ud(depositSize + 1), true, 0, address(0));
    }

    function test_trade_RevertIf_SellOptions_WithInsufficientBidLiquidity() public {
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientBidLiquidity.selector);
        pool.trade(ud(depositSize + 1), false, 0, address(0));
    }

    function test_trade_RevertIf_TradeSizeIsZero() public {
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.trade(ud(0), true, 0, address(0));
    }

    function test_trade_RevertIf_Expired() public {
        vm.warp(poolKey.maturity);

        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.trade(ud(1), true, 0, address(0));
    }
}
