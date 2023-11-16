// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {PRBMathExtra} from "contracts/libraries/PRBMathExtra.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {WAD, ZERO} from "contracts/libraries/Constants.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";

import {console} from "forge-std/console.sol";

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

        oracleAdapter.setPrice(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot, strike, ud(134246575342465753), ud(1.54e18));
        volOracle.setVolatility(base, spot, ud(1100e18), ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot, ud(1100e18), ud(134246575342465753), ud(1.54e18));

        volOracle.setVolatility(base, spot - ud(500 ether), strike, ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot - ud(500 ether), strike, ud(134246575342465753), ud(1.54e18));
        volOracle.setVolatility(base, spot + ud(500 ether), strike, ud(19178082191780821), ud(1.54e18));
        volOracle.setVolatility(base, spot + ud(500 ether), strike, ud(134246575342465753), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);
    }

    function test_computeCLevel_Success() public {
        UD60x18[7] memory utilisation = [ud(0e18), ud(0.2e18), ud(0.4e18), ud(0.6e18), ud(0.8e18), ud(1e18), ud(1e18)];

        UD60x18[7] memory duration = [ud(0e18), ud(3e18), ud(6e18), ud(9e18), ud(12e18), ud(15e18), ud(250e18)];

        UD60x18[7] memory expected = [
            ud(1e18),
            ud(1e18),
            ud(1e18),
            ud(1.007915959186644182e18),
            ud(1.045034261503684539e18),
            ud(1.125e18),
            ud(1e18)
        ];

        for (uint256 i = 0; i < utilisation.length; i++) {
            assertEq(
                vault.computeCLevel(utilisation[i], duration[i], ud(3e18), ud(1e18), ud(1.2e18), ud(0.005e18)),
                expected[i]
            );
        }
    }

    function test_cLevelGeoMean_ReturnCorrectOutput() public {
        vault.setAlphaCLevel(ud(0.15 ether));
        vault.setMinCLevel(ud(1.05 ether));
        vault.setMaxCLevel(ud(1.2 ether));
        vault.setHourlyDecayDiscount(ud(0.005 ether));

        UD60x18 size = ud(4.3 ether);

        UD60x18[6] memory totalAssets = [ud(10e18), ud(12e18), ud(12.5e18), ud(13e18), ud(14e18), ud(18e18)];
        UD60x18[6] memory totalLockedAssets = [ud(0e18), ud(0e18), ud(7.21e18), ud(8.1e18), ud(3e18), ud(13e18)];

        vault.setLastTradeTimestamp(82800);
        vault.setTimestamp(165600);

        UD60x18[6] memory expected = [
            ud(1.05e18),
            ud(1.05e18),
            ud(1.1025950417585488e18),
            ud(1.1087367093170641e18),
            ud(1.0650306024789773e18),
            ud(1.1167254362471732e18)
        ];

        for (uint256 i = 0; i < 2; i++) {
            if (i == 0) {
                vault.setIsCall(true);
            } else {
                vault.setIsCall(false);
            }
            for (uint256 j = 0; j < totalAssets.length; j++) {
                assertApproxEqAbs(
                    vault.computeCLevelGeoMean(totalAssets[j], totalLockedAssets[j], size).unwrap(),
                    expected[j].unwrap(),
                    1000
                );
            }
        }
    }

    function test_getQuote_ReturnCorrectQuote() public {
        setup();

        assertApproxEqAbs(
            fromTokenDecimals(vault.getQuote(poolKey, ud(3e18), true, address(0))).unwrap(),
            isCallTest ? 0.161791878138208136e18 : 480.701186e18,
            isCallTest ? 0.000001e18 : 0.01e18
        );
    }

    function test_getQuote_Success_Sell() public {
        setup();
        enableSell();

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        // it should return the correct quote
        UD60x18 size = ud(3 ether);
        uint256 premium = vault.getQuote(poolKey, size, false, address(0));

        UD60x18 tau = ud(maturity - timestamp) / ud(365 days);
        UD60x18 sigma = volOracle.getVolatility(address(base), spot, strike, tau);
        UD60x18 bsPremium = vault.getBlackScholesPrice(
            spot,
            strike,
            tau,
            sigma,
            volOracle.getRiskFreeRate(),
            isCallTest
        );

        UD60x18 avgPremium = vault.getAveragePremium(strike, maturity);

        UD60x18 expected = fromTokenDecimals(toTokenDecimals(size * PRBMathExtra.min(bsPremium, avgPremium)));

        // Check quote
        assertEq(expected, fromTokenDecimals(premium));
    }

    function test_getQuote_RevertIf_SellIsDisabled() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        // it revert if sell is disabled
        vm.expectRevert(IVault.Vault__SellDisabled.selector);
        vault.getQuote(poolKey, ud(1 ether), false, address(0));
    }

    function test_getQuote_RevertIf_InsufficientShorts() public {
        vm.expectRevert(IVault.Vault__InsufficientShorts.selector);
        vault.getQuote(poolKey, ud(3 ether), false, address(0));
    }

    function test_getQuote_ReturnCorrectQuote_ForPoolNotDeployed() public {
        setup();

        poolKey.strike = ud(1100e18);

        assertApproxEqAbs(
            fromTokenDecimals(vault.getQuote(poolKey, ud(3e18), true, address(0))).unwrap(),
            isCallTest ? 0.161791878138208136e18 : 480.701186e18,
            isCallTest ? 0.000001e18 : 0.01e18
        );
    }

    function test_getQuote_ForFullyUtilisedVaultWithUnsettledOptions() public {
        setup();
        console.log(vault.totalAssets());

        UD60x18 tradeSize = ud(4 ether);
        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        vm.startPrank(users.trader);
        IERC20 token = IERC20(getPoolToken());
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));
        console.log(vault.totalAssets());
        console.log(vault.totalLockedAssets().unwrap());

        vault.setTimestamp(poolKey.maturity);
        poolKey.maturity = 1678435200;
        assertApproxEqAbs(
            fromTokenDecimals(vault.getQuote(poolKey, ud(3e18), true, address(0))).unwrap(),
            isCallTest ? 0.160026767588644148e18 : 475.26231e18,
            isCallTest ? 0.000001e18 : 0.01e18
        );
        assertEq(vault.totalLockedAssets(), isCallTest ? tradeSize : tradeSize * strike);
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

        oracleAdapter.setPrice(spot);
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

        oracleAdapter.setPrice(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.getQuote(poolKey, ud(3e18), true, address(0));
    }

    function test_trade_CallSettleInternally() public {
        setup();

        UD60x18 protocolFees = ud(1e18);
        vault.setProtocolFees(protocolFees);
        IERC20 token = IERC20(getPoolToken());

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;

        deal(address(token), address(vault), toTokenDecimals(depositSize + protocolFees));

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);

        vm.expectEmit();
        emit ClaimProtocolFees(FEE_RECEIVER, toTokenDecimals(protocolFees));
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));
    }

    function test_trade_ProcessTradeCorrectly() public {
        setup();

        UD60x18 tradeSize = ud(3e18);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        uint256 depositSize = toTokenDecimals(isCallTest ? ud(5e18) : ud(5e18) * strike);

        uint256 collateral = toTokenDecimals(isCallTest ? ud(3e18) : ud(3e18) * strike);

        uint256 mintingFee = pool.takerFee(address(0), tradeSize, 0, true, false);

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

    function test_trade_AnnihilateFor_ProcessTradeCorrectly() public {
        setup();

        IERC20 token = IERC20(getPoolToken());

        // Deal out collateral to trader
        uint256 initialCollateral = toTokenDecimals(
            contractsToCollateral(isCallTest ? ud(1000 ether) : ud(1000 ether) * poolKey.strike)
        );

        deal(address(token), users.trader, initialCollateral);

        vm.prank(users.trader);
        token.approve(address(router), initialCollateral);

        // Make trader underwrite 2 option contracts to receive 2 shorts
        UD60x18 size = ud(2 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true, false);

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](2);
            actions[0] = IUserSettings.Action.Annihilate;
            actions[1] = IUserSettings.Action.WriteFrom;

            bool[] memory authorization = new bool[](2);
            authorization[0] = true;
            authorization[1] = true;

            vm.prank(users.trader);
            userSettings.setActionAuthorization(address(vault), actions, authorization);
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](1);
            actions[0] = IUserSettings.Action.WriteFrom;

            bool[] memory authorization = new bool[](1);
            authorization[0] = true;

            vm.prank(users.trader);
            userSettings.setActionAuthorization(users.lp, actions, authorization);
        }

        vm.prank(users.lp);
        pool.writeFrom(users.trader, users.lp, size, address(0));

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), ud(2 ether));
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), ud(0 ether));

        // Trader buys long contracts from vault and annihilates shorts
        UD60x18 tradeSize = ud(3 ether);
        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        uint256 depositSize = toTokenDecimals(isCallTest ? ud(5e18) : ud(5e18) * strike);
        uint256 collateral = toTokenDecimals(isCallTest ? tradeSize : tradeSize * strike);
        uint256 mintingFee = pool.takerFee(address(0), tradeSize, 0, true, false);

        // Check that long contracts have been transferred to trader
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), ud(0 ether));
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), ud(1 ether));
        // Check that short contracts have been transferred to vault
        assertEq(pool.balanceOf(address(vault), PoolStorage.SHORT), tradeSize);
        // Check that premium has been transferred to vault
        assertEq(token.balanceOf(address(vault)), depositSize + totalPremium - collateral - mintingFee);
        // Check that listing has been successfully added to vault
        assertEq(vault.getPositionSize(strike, maturity), tradeSize);
        // Check that collateral and minting fee have been transferred to pool
        assertEq(token.balanceOf(address(pool)), collateral + fee + mintingFee);
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

        uint256 depositSize = toTokenDecimals(isCallTest ? ud(5e18) : ud(5e18) * strike);
        uint256 collateral = toTokenDecimals(isCallTest ? ud(3e18) : ud(3e18) * strike);

        uint256 mintingFee = pool.takerFee(address(0), tradeSize, 0, true, false);

        vm.stopPrank();
        vm.prank(referrer);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        referral.claimRebate(tokens);

        // primary rebate = 5% = 1/20
        uint256 totalReferrerRebate = mintingFee / 20;
        assertEq(token.balanceOf(referrer), totalReferrerRebate);

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

    function enableSell() internal {
        settings[10] = 1;

        vault.updateSettings(abi.encode(settings));
    }

    function test_trade_Success_SellToClose_NoSpread() public {
        setup();
        enableSell();

        IERC20 token = IERC20(getPoolToken());

        UD60x18 tradeSize = ud(4 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        // trader: Buy-To-Open
        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        // trader: Sell-To-Close
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalLockedAssetsBefore = toTokenDecimals(vault.totalLockedAssets());
        uint256 traderAssetsBefore = token.balanceOf(users.trader);

        UD60x18 size = ud(2 ether);

        totalPremium = vault.getQuote(poolKey, size, false, address(0));
        IUnderwriterVault.QuoteInternal memory quote = vault.exposed_getQuoteInternal(poolKey, size, false, address(0));

        // Trader performs sell-to-close
        pool.setApprovalForAll(address(vault), true);
        vault.trade(poolKey, size, false, totalPremium, address(0));

        uint256 collateral = isCallTest ? size.unwrap() : toTokenDecimals(size * strike);

        // it should annihilate the shorts and longs from the trader and the vault
        assertEq(pool.balanceOf(address(vault), PoolStorage.SHORT), 2 ether);
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 2 ether);

        // it should release the collateral to the vault after annihilation and subtract the premium given to trader
        assertEq(vault.totalAssets(), totalAssetsBefore + collateral - toTokenDecimals(quote.premium));

        // it should transfer the premium to the trader
        assertEq(token.balanceOf(users.trader), traderAssetsBefore + toTokenDecimals(quote.premium));

        // it should decrease the internal position size
        assertEq(vault.getPositionSize(strike, maturity), ud(2 ether));

        // it should decrease totalLockedAssets by the amount of collateral released
        assertEq(vault.totalLockedAssets(), fromTokenDecimals(totalLockedAssetsBefore - collateral));
    }

    function test_trade_Success_SellToClose_WithSpread() public {
        setup();
        enableSell();

        IERC20 token = IERC20(getPoolToken());

        UD60x18 tradeSize = ud(4 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        // trader: Buy-To-Open
        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        // Update spot to be lower if call and higher if put
        UD60x18 spotPrice = vault.getSpotPrice();
        vault.setSpotPrice(isCallTest ? spotPrice - ud(500 ether) : spotPrice + ud(500 ether));

        // trader: Sell-To-Close
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalLockedAssetsBefore = toTokenDecimals(vault.totalLockedAssets());
        uint256 traderAssetsBefore = token.balanceOf(users.trader);
        UD60x18 protocolFeesBefore = vault.getProtocolFees();
        IUnderwriterVault.LockedSpreadInternal memory lockedSpreadBefore = vault.getLockedSpreadInternal();

        UD60x18 size = ud(2 ether);

        totalPremium = vault.getQuote(poolKey, size, false, address(0));
        IUnderwriterVault.QuoteInternal memory quote = vault.exposed_getQuoteInternal(poolKey, size, false, address(0));
        UD60x18 performanceFee = fromTokenDecimals(toTokenDecimals((vault.getPerformanceFeeRate() * quote.spread)));

        // Trader performs sell-to-close
        pool.setApprovalForAll(address(vault), true);
        vm.expectEmit();
        emit ClaimProtocolFees(FEE_RECEIVER, toTokenDecimals(protocolFeesBefore));
        emit PerformanceFeePaid(FEE_RECEIVER, toTokenDecimals(performanceFee));
        emit Trade(msg.sender, address(pool), size, false, quote.premium, ZERO, ZERO, quote.spread);
        emit UpdateQuotes();
        vault.trade(poolKey, size, false, totalPremium, address(0));

        uint256 collateral = isCallTest ? size.unwrap() : toTokenDecimals(size * strike);

        // it should annihilate the shorts and longs from the trader and the vault
        assertEq(pool.balanceOf(address(vault), PoolStorage.SHORT), 2 ether);
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 2 ether);

        // it should release the collateral to the vault after annihilation and subtract the premium given to trader
        assertEq(
            vault.totalAssets(),
            totalAssetsBefore + collateral - toTokenDecimals(quote.premium) - toTokenDecimals(performanceFee)
        );

        // it should transfer the premium to the trader
        assertEq(token.balanceOf(users.trader), traderAssetsBefore + toTokenDecimals(quote.premium));

        // it should decrease the internal position size
        assertEq(vault.getPositionSize(strike, maturity), ud(2 ether));

        // it should decrease totalLockedAssets by the amount of collateral released
        assertEq(vault.totalLockedAssets(), fromTokenDecimals(totalLockedAssetsBefore - collateral));

        // it should increase the total locked spread
        UD60x18 spread = quote.spread - performanceFee;
        IUnderwriterVault.LockedSpreadInternal memory lockedSpread = vault.getLockedSpreadInternal();
        assertEq(lockedSpread.totalLockedSpread, lockedSpreadBefore.totalLockedSpread + spread);

        // it should increase the total spread unlocking rate
        UD60x18 rate = spread / ud((maturity - timestamp) * WAD);
        assertEq(lockedSpread.spreadUnlockingRate, lockedSpreadBefore.spreadUnlockingRate + rate);

        // it should update the timestamp of the last trade
        assertEq(lockedSpread.lastSpreadUnlockUpdate, timestamp);

        // it should increase the the protocol fees by the performance fee
        assertEq(vault.getProtocolFees(), performanceFee);
    }

    function test_trade_Success_SellToOpen_NoSpread() public {
        setup();
        enableSell();

        IERC20 token = IERC20(getPoolToken());

        UD60x18 tradeSize = ud(4 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        // trader: Buy-To-Open
        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));
        vm.stopPrank();

        // underwriter: Sell-To-Open
        vm.startPrank(users.underwriter);

        UD60x18 size = ud(2 ether);
        uint256 collateral = isCallTest ? size.unwrap() : toTokenDecimals(size * strike);
        deal(address(token), users.underwriter, collateral);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalLockedAssetsBefore = toTokenDecimals(vault.totalLockedAssets());
        uint256 underwriterAssetsBefore = token.balanceOf(users.underwriter);

        totalPremium = vault.getQuote(poolKey, size, false, address(0));

        // Underwriter performs sell-to-open
        token.approve(address(vault), collateral);
        vault.trade(poolKey, size, false, totalPremium, address(0));

        // it should collect the (collateral - premium) from the underwriter
        assertEq(vault.totalAssets(), totalAssetsBefore + collateral - totalPremium);

        // it should transfer the shorts to the underwriter
        assertEq(pool.balanceOf(users.underwriter, PoolStorage.SHORT), 2 ether);

        // it should transfer the premium to the trader
        assertEq(token.balanceOf(users.underwriter), underwriterAssetsBefore - collateral + totalPremium);

        // it should decrease the internal position size
        assertEq(vault.getPositionSize(strike, maturity), ud(2 ether));

        // it should decrease totalLockedAssets by the amount of collateral released
        assertEq(vault.totalLockedAssets(), fromTokenDecimals(totalLockedAssetsBefore - collateral));
    }

    function test_trade_Success_SellToOpen_WithSpread() public {
        setup();
        enableSell();

        IERC20 token = IERC20(getPoolToken());

        UD60x18 tradeSize = ud(4 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        // trader: Buy-To-Open
        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));
        vm.stopPrank();

        // underwriter: Sell-To-Open
        vm.startPrank(users.underwriter);

        UD60x18 size = ud(2 ether);
        uint256 collateral = isCallTest ? size.unwrap() : toTokenDecimals(size * strike);
        deal(address(token), users.underwriter, collateral);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalLockedAssetsBefore = toTokenDecimals(vault.totalLockedAssets());
        uint256 underwriterAssetsBefore = token.balanceOf(users.underwriter);
        UD60x18 protocolFeesBefore = vault.getProtocolFees();
        IUnderwriterVault.LockedSpreadInternal memory lockedSpreadBefore = vault.getLockedSpreadInternal();

        totalPremium = vault.getQuote(poolKey, size, false, address(0));
        IUnderwriterVault.QuoteInternal memory quote = vault.exposed_getQuoteInternal(poolKey, size, false, address(0));
        UD60x18 performanceFee = fromTokenDecimals(toTokenDecimals((vault.getPerformanceFeeRate() * quote.spread)));

        // Underwriter performs sell-to-open
        token.approve(address(vault), collateral);
        vm.expectEmit();
        emit ClaimProtocolFees(FEE_RECEIVER, toTokenDecimals(protocolFeesBefore));
        emit PerformanceFeePaid(FEE_RECEIVER, toTokenDecimals(performanceFee));
        emit Trade(msg.sender, address(pool), size, false, quote.premium, ZERO, ZERO, quote.spread);
        emit UpdateQuotes();
        vault.trade(poolKey, size, false, totalPremium, address(0));

        // it should collect the (collateral - premium) from the underwriter
        assertEq(vault.totalAssets(), totalAssetsBefore + collateral - totalPremium);

        // it should transfer the shorts to the underwriter
        assertEq(pool.balanceOf(users.underwriter, PoolStorage.SHORT), 2 ether);

        // it should transfer the premium to the trader
        assertEq(token.balanceOf(users.underwriter), underwriterAssetsBefore - collateral + totalPremium);

        // it should decrease the internal position size
        assertEq(vault.getPositionSize(strike, maturity), ud(2 ether));

        // it should decrease totalLockedAssets by the amount of collateral released
        assertEq(vault.totalLockedAssets(), fromTokenDecimals(totalLockedAssetsBefore - collateral));

        // it should increase the total locked spread
        UD60x18 spread = quote.spread - performanceFee;
        IUnderwriterVault.LockedSpreadInternal memory lockedSpread = vault.getLockedSpreadInternal();
        assertEq(lockedSpread.totalLockedSpread, lockedSpreadBefore.totalLockedSpread + spread);

        // it should increase the total spread unlocking rate
        UD60x18 rate = spread / ud((maturity - timestamp) * WAD);
        assertEq(lockedSpread.spreadUnlockingRate, lockedSpreadBefore.spreadUnlockingRate + rate);

        // it should update the timestamp of the last trade
        assertEq(lockedSpread.lastSpreadUnlockUpdate, timestamp);

        // it should increase the the protocol fees by the performance fee
        assertEq(vault.getProtocolFees(), performanceFee);
    }

    function test_trade_Success_SellToCloseThenSellToOpen_NoSpread() public {
        setup();
        enableSell();

        IERC20 token = IERC20(getPoolToken());

        UD60x18 tradeSize = ud(2 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        // trader: Buy-To-Open
        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));
        vm.stopPrank();

        // Underwriter
        vm.startPrank(users.underwriter);

        UD60x18 size = ud(2 ether);
        totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));
        uint256 collateral = isCallTest ? size.unwrap() : toTokenDecimals(size * strike);
        deal(address(token), users.underwriter, collateral + totalPremium);

        // underwriter: Buy-To-Open
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, size, true, totalPremium + totalPremium / 10, address(0));

        // underwriter: Sell-To-Close and Sell-To-Open
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalLockedAssetsBefore = toTokenDecimals(vault.totalLockedAssets());
        uint256 underwriterAssetsBefore = token.balanceOf(users.underwriter);

        size = ud(4 ether);

        totalPremium = vault.getQuote(poolKey, size, false, address(0));
        // IUnderwriterVault.QuoteInternal memory quote = vault.exposed_getQuoteInternal(poolKey, size, false, address(0));

        // Underwriter performs sell-to-open
        token.approve(address(vault), collateral);
        pool.setApprovalForAll(address(vault), true);
        vault.trade(poolKey, size, false, totalPremium, address(0));

        // it should collect the (collateral - premium) from the underwriter
        assertEq(vault.totalAssets(), totalAssetsBefore + 2 * collateral - totalPremium);

        // it should transfer the shorts to the underwriter
        assertEq(pool.balanceOf(users.underwriter, PoolStorage.SHORT), 2 ether);

        // it should transfer the premium to the trader
        assertEq(token.balanceOf(users.underwriter), underwriterAssetsBefore - collateral + totalPremium);

        // it should decrease the internal position size
        assertEq(vault.getPositionSize(strike, maturity), ud(0 ether));

        // it should decrease totalLockedAssets by the amount of collateral released
        assertEq(vault.totalLockedAssets(), fromTokenDecimals(totalLockedAssetsBefore - 2 * collateral));
    }

    function test_trade_Success_SellToCloseThenSellToOpen_WithSpread() public {
        setup();
        enableSell();

        IERC20 token = IERC20(getPoolToken());

        UD60x18 tradeSize = ud(2 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        // trader: Buy-To-Open
        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));
        vm.stopPrank();

        // Underwriter
        vm.startPrank(users.underwriter);

        UD60x18 size = ud(2 ether);
        totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));
        uint256 collateral = isCallTest ? size.unwrap() : toTokenDecimals(size * strike);
        deal(address(token), users.underwriter, collateral + totalPremium);

        // underwriter: Buy-To-Open
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, size, true, totalPremium + totalPremium / 10, address(0));

        // underwriter: Sell-To-Close and Sell-To-Open
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalLockedAssetsBefore = toTokenDecimals(vault.totalLockedAssets());
        uint256 underwriterAssetsBefore = token.balanceOf(users.underwriter);
        UD60x18 protocolFeesBefore = vault.getProtocolFees();
        IUnderwriterVault.LockedSpreadInternal memory lockedSpreadBefore = vault.getLockedSpreadInternal();

        size = ud(4 ether);

        totalPremium = vault.getQuote(poolKey, size, false, address(0));
        IUnderwriterVault.QuoteInternal memory quote = vault.exposed_getQuoteInternal(poolKey, size, false, address(0));
        UD60x18 performanceFee = fromTokenDecimals(toTokenDecimals((vault.getPerformanceFeeRate() * quote.spread)));

        // Underwriter performs sell-to-open
        token.approve(address(vault), collateral);
        pool.setApprovalForAll(address(vault), true);
        vm.expectEmit();
        emit ClaimProtocolFees(FEE_RECEIVER, toTokenDecimals(protocolFeesBefore));
        emit PerformanceFeePaid(FEE_RECEIVER, toTokenDecimals(performanceFee));
        emit Trade(msg.sender, address(pool), size, false, quote.premium, ZERO, ZERO, quote.spread);
        emit UpdateQuotes();
        vault.trade(poolKey, size, false, totalPremium, address(0));

        // it should collect the (collateral - premium) from the underwriter
        assertEq(vault.totalAssets(), totalAssetsBefore + 2 * collateral - totalPremium);

        // it should transfer the shorts to the underwriter
        assertEq(pool.balanceOf(users.underwriter, PoolStorage.SHORT), 2 ether);

        // it should transfer the premium to the trader
        assertEq(token.balanceOf(users.underwriter), underwriterAssetsBefore - collateral + totalPremium);

        // it should decrease the internal position size
        assertEq(vault.getPositionSize(strike, maturity), ud(0 ether));

        // it should decrease totalLockedAssets by the amount of collateral released
        assertEq(vault.totalLockedAssets(), fromTokenDecimals(totalLockedAssetsBefore - 2 * collateral));

        // it should increase the total locked spread
        UD60x18 spread = quote.spread - performanceFee;
        IUnderwriterVault.LockedSpreadInternal memory lockedSpread = vault.getLockedSpreadInternal();
        assertEq(lockedSpread.totalLockedSpread, lockedSpreadBefore.totalLockedSpread + spread);

        // it should increase the total spread unlocking rate
        UD60x18 rate = spread / ud((maturity - timestamp) * WAD);
        assertEq(lockedSpread.spreadUnlockingRate, lockedSpreadBefore.spreadUnlockingRate + rate);

        // it should update the timestamp of the last trade
        assertEq(lockedSpread.lastSpreadUnlockUpdate, timestamp);

        // it should increase the the protocol fees by the performance fee
        assertEq(vault.getProtocolFees(), performanceFee);
    }

    function test_trade_RevertIf_AboveSlippage_Sell() public {
        setup();
        enableSell();

        UD60x18 tradeSize = ud(3 ether);

        uint256 totalPremium = vault.getQuote(poolKey, tradeSize, true, address(0));

        IERC20 token = IERC20(getPoolToken());

        vm.startPrank(users.trader);
        token.approve(address(vault), totalPremium + totalPremium / 10);
        vault.trade(poolKey, tradeSize, true, totalPremium + totalPremium / 10, address(0));

        // Sell-To-Close
        totalPremium = vault.getQuote(poolKey, tradeSize, false, address(0));

        pool.setApprovalForAll(address(vault), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault__AboveMaxSlippage.selector,
                fromTokenDecimals(totalPremium),
                fromTokenDecimals(totalPremium + totalPremium / 10)
            )
        );
        vault.trade(poolKey, tradeSize, false, totalPremium + totalPremium / 10, address(0));
    }

    function test_trade_UseLongReceiverAsTaker() public {
        setup();

        UD60x18 tradeSize = ud(3e18);
        uint256 fee = pool.takerFee(users.trader, tradeSize, 0, true, false);

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
            fromTokenDecimals(fee)
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
                isCallTest ? 0.161791878138208136e18 : 480.701186e18,
                isCallTest ? 0.080895939069104068e18 : 240.350593e18
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

        oracleAdapter.setPrice(spot);
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

        oracleAdapter.setPrice(spot);
        volOracle.setVolatility(base, spot, strike, ud(19178082191780821), ud(1.54e18));

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.trade(poolKey, ud(3e18), true, 1000e18, address(0));
    }

    function test_getSettings_ReturnExpectedValue() public {
        assertEq(vault.getSettings(), abi.encode(settings));

        uint256[] memory newSettings = new uint256[](11);

        for (uint256 i = 0; i < settings.length; i++) {
            newSettings[i] = settings[i] * 2;
        }

        vault.updateSettings(abi.encode(newSettings));

        assertEq(vault.getSettings(), abi.encode(newSettings));
    }

    function test_updateSettings_RevertIf_NotOwner() public {
        vm.prank(users.trader);

        vm.expectRevert(IVault.Vault__NotAuthorized.selector);
        vault.updateSettings(abi.encode(settings));
    }

    function test_updateSettings_RevertIf_InvalidSettings_EnableSell() public {
        settings[10] = 2;

        vm.expectRevert(IVault.Vault__InvalidSettingsUpdate.selector);
        vault.updateSettings(abi.encode(settings));
    }
}
