// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

abstract contract UnderwriterVaultVaultTest is UnderwriterVaultDeployTest {
    UD60x18 spot = UD60x18.wrap(1000e18);
    UD60x18 strike = UD60x18.wrap(1100e18);
    uint256 timestamp = 1677225600;
    uint256 maturity = 1677830400;

    function setup() internal {
        poolKey.maturity = maturity;
        poolKey.strike = strike;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot, strike, ud(134246575342465753), ud(1.54e18));
        volOracle.setVolatility(base, spot, ud(1050e18), ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot, ud(1050e18), ud(134246575342465753), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);
    }

    function test_computeCLevel_Success() public {
        UD60x18[6] memory utilisation = [ud(0e18), ud(0.2e18), ud(0.4e18), ud(0.6e18), ud(0.8e18), ud(1e18)];

        UD60x18[6] memory duration = [ud(0e18), ud(3e18), ud(6e18), ud(9e18), ud(12e18), ud(15e18)];

        UD60x18[6] memory expected = [
            ud(1e18),
            ud(1e18),
            ud(1e18),
            ud(1.007915959186644182e18),
            ud(1.045034261503684539e18),
            ud(1.125e18)
        ];

        for (uint256 i = 0; i < utilisation.length; i++) {
            assertEq(
                vault.computeCLevel(utilisation[i], duration[i], ud(3e18), ud(1e18), ud(1.2e18), ud(0.005e18)),
                expected[i]
            );
        }
    }

    function test_getQuote_ReturnCorrectQuote() public {
        setup();

        assertApproxEqAbs(
            scaleDecimals(vault.getQuote(poolKey, ud(3e18), true, address(0))).unwrap(),
            isCallTest ? 0.15828885563446596e18 : 469.9068335343156e18,
            isCallTest ? 0.000001e18 : 0.01e18
        );
    }

    function test_getQuote_ReturnCorrectQuote_ForPoolNotDeployed() public {
        setup();

        poolKey.strike = ud(1050e18);

        assertApproxEqAbs(
            scaleDecimals(vault.getQuote(poolKey, ud(3e18), true, address(0))).unwrap(),
            isCallTest ? 0.20945141965280406e18 : 363.255965e18,
            isCallTest ? 0.000001e18 : 0.01e18
        );
    }

    function test_getQuote_RevertIf_NotEnoughAvailableAssets() public {
        setup();

        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        vault.getQuote(poolKey, ud(6e18), true, address(0));
    }

    function test_getQuote_RevertIf_ZeroSize() public {
        setup();

        vm.expectRevert(IVault.Vault__ZeroSize.selector);
        vault.getQuote(poolKey, ud(0), true, address(0));
    }

    function test_getQuote_RevertIf_ZeroStrike() public {
        setup();

        poolKey.strike = ud(0);

        vm.expectRevert(IVault.Vault__StrikeZero.selector);
        vault.getQuote(poolKey, ud(3e18), true, address(0));
    }

    function test_getQuote_RevertIf_BuyWithWrongVault() public {
        setup();

        poolKey.isCallPool = !poolKey.isCallPool;

        vm.expectRevert(IVault.Vault__OptionTypeMismatchWithVault.selector);
        vault.getQuote(poolKey, ud(3e18), true, address(0));
    }

    function test_getQuote_RevertIf_TryingToSellToVault() public {
        setup();

        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.getQuote(poolKey, ud(3e18), false, address(0));
    }

    function test_getQuote_RevertIf_TryingToBuyExpiredOption() public {
        setup();

        vault.setTimestamp(maturity + 3 hours);

        vm.expectRevert(abi.encodeWithSelector(IVault.Vault__OptionExpired.selector, 1677841200, 1677830400));
        vault.getQuote(poolKey, ud(3e18), true, address(0));
    }

    function test_getQuote_RevertIf_TryingToBuyOptionNotWithinDTEBounds() public {
        timestamp = 1676620800;
        maturity = 1682668800;

        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot, strike, ud(134246575342465753), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDTEBounds.selector);
        vault.getQuote(poolKey, ud(3e18), true, address(0));
    }

    function test_getQuote_RevertIf_TryingToBuyOptionNotWithinDeltaBounds() public {
        timestamp = 1677225600;
        maturity = 1677830400;
        strike = ud(1500e18);

        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.getQuote(poolKey, ud(3e18), true, address(0));
    }

    function test_trade_ProcessTradeCorrectly() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        uint256 depositSize = scaleDecimals(isCallTest ? ud(5e18) : ud(5e18) * strike);

        uint256 collateral = scaleDecimals(isCallTest ? ud(3e18) : ud(3e18) * strike);

        uint256 mintingFee = pool.takerFee(address(0), tradeSize, 0, false);

        // Check that long contracts have been transferred to trader
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        // Check that short contracts have been transferred to vault
        assertEq(pool.balanceOf(address(vault), PoolStorage.SHORT), tradeSize);
        // Check that premium has been transferred to vault
        assertEq(token.balanceOf(address(vault)), depositSize + totalPremium - collateral - mintingFee);
        // Check that listing has been successfully added to vault
        assertEq(vault.getPositionSize(strike, maturity), tradeSize);
        // Check that collateral and minting fee have been transferred to pool
        assertEq(token.balanceOf(address(pool)), collateral + mintingFee);
    }

    function test_trade_ProcessTradeCorrectly_WithReferral() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        address referrer = address(12345);

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, referrer);

        uint256 depositSize = scaleDecimals(isCallTest ? ud(5e18) : ud(5e18) * strike);
        uint256 collateral = scaleDecimals(isCallTest ? ud(3e18) : ud(3e18) * strike);

        uint256 mintingFee = pool.takerFee(address(0), tradeSize, 0, false);

        vm.stopPrank();
        vm.prank(referrer);
        referral.claimRebate();

        // primary rebate = 5% = 1/20
        uint256 totalReferrerRebate = mintingFee / 20;
        assertEq(token.balanceOf(referrer), totalReferrerRebate, "a");

        // Check that long contracts have been transferred to trader
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        // Check that short contracts have been transferred to vault
        assertEq(pool.balanceOf(address(vault), PoolStorage.SHORT), tradeSize);
        // Check that premium has been transferred to vault
        assertEq(token.balanceOf(address(vault)), depositSize + totalPremium - collateral - mintingFee);
        // Check that listing has been successfully added to vault
        assertEq(vault.getPositionSize(strike, maturity), tradeSize);
        // Check that collateral and minting fee have been transferred to pool
        assertEq(token.balanceOf(address(pool)), collateral + mintingFee - totalReferrerRebate);
    }

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        address indexed taker,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 protocolFee
    );

    function test_trade_UseLongReceiverAsTaker() public {
        setup();

        UD60x18 tradeSize = ud(3e18);
        uint256 fee = pool.takerFee(users.trader, tradeSize, 0, true);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);

        vm.expectEmit();

        emit WriteFrom(
            address(vault),
            users.trader,
            users.trader,
            tradeSize,
            contractsToCollateral(tradeSize),
            ud(scaleDecimalsTo(fee))
        );

        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        vm.stopPrank();
    }

    function test_trade_RevertIf_NotEnoughAvailableCapital() public {
        setup();

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        UD60x18 tradeSize = ud(6e18);
        token.approve(address(vault), 1000e18);

        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        vault.trade(poolKey, tradeSize, true, 1000e18, address(0));
    }

    function test_trade_RevertIf_AboveSlippage() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault__AboveMaxSlippage.selector,
                isCallTest ? 158288659375834262 : 469906637275684065913,
                isCallTest ? 79144329687917131 : 234953318000000000000
            )
        );

        vault.trade(poolKey, tradeSize, true, totalPremium / 2, address(0));
    }

    function test_trade_RevertIf_PoolDoesNotExist() public {
        setup();

        UD60x18 tradeSize = ud(3e18);
        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), 1000e18);

        poolKey.maturity = poolKey.maturity + 7 days;

        vm.expectRevert(IVault.Vault__OptionPoolNotListed.selector);
        vault.trade(poolKey, tradeSize, true, 1000e18, address(0));
    }

    function test_trade_RevertIf_ZeroSize() public {
        setup();

        UD60x18 tradeSize = ud(0);

        vm.startPrank(users.trader);

        vm.expectRevert(IVault.Vault__ZeroSize.selector);
        vault.trade(poolKey, tradeSize, true, 1000e18, address(0));
    }

    function test_trade_RevertIf_ZeroStrike() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        vm.startPrank(users.trader);

        poolKey.strike = ud(0);

        vm.expectRevert(IVault.Vault__StrikeZero.selector);
        vault.trade(poolKey, tradeSize, true, 1000e18, address(0));
    }

    function test_trade_RevertIf_BuyWithWrongVault() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        vm.startPrank(users.trader);

        poolKey.isCallPool = !poolKey.isCallPool;

        vm.expectRevert(IVault.Vault__OptionTypeMismatchWithVault.selector);
        vault.trade(poolKey, tradeSize, true, 1000e18, address(0));
    }

    function test_trade_RevertIf_TryingToSellToVault() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        vm.startPrank(users.trader);

        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.trade(poolKey, tradeSize, false, 1000e18, address(0));
    }

    function test_trade_RevertIf_TryingToBuyExpiredOption() public {
        setup();

        vault.setTimestamp(maturity + 3 hours);
        UD60x18 tradeSize = ud(3e18);

        vm.startPrank(users.trader);

        vm.expectRevert(abi.encodeWithSelector(IVault.Vault__OptionExpired.selector, 1677841200, 1677830400));
        vault.trade(poolKey, tradeSize, true, 1000e18, address(0));
    }

    function test_trade_RevertIf_TryingToBuyOptionNotWithinDTEBounds() public {
        timestamp = 1676620800;
        maturity = 1682668800;

        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot, strike, ud(134246575342465753), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDTEBounds.selector);
        vault.trade(poolKey, ud(3e18), true, 1000e18, address(0));
    }

    function test_trade_RevertIf_TryingToBuyOptionNotWithinDeltaBounds() public {
        timestamp = 1677225600;
        maturity = 1677830400;
        strike = ud(1500e18);

        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.trade(poolKey, ud(3e18), true, 1000e18, address(0));
    }
}
