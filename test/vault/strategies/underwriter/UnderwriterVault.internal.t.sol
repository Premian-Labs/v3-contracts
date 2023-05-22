// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

abstract contract UnderwriterVaultInternalTest is UnderwriterVaultDeployTest {
    function setupSpreadVault() internal {
        startTime = 1678435200 + 500 * 7 days;
        t0 = startTime + 7 days;
        t1 = startTime + 10 days;
        t2 = startTime + 14 days;

        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](3);

        infos[0].maturity = t0;
        infos[1].maturity = t1;
        infos[2].maturity = t2;

        vault.setListingsAndSizes(infos);
        vault.setLastSpreadUnlockUpdate(startTime);

        UD60x18 totalLockedSpread = ud(1.24e18 + 5.56e18 + 11.2e18);
        UD60x18 spreadUnlockingRateT0 = ud(1.24e18) / ud(7 days * 1e18);
        UD60x18 spreadUnlockingRateT1 = ud(5.56e18) / ud(10 days * 1e18);
        UD60x18 spreadUnlockingRateT2 = ud(11.2e18) / ud(14 days * 1e18);
        UD60x18 spreadUnlockingRate = spreadUnlockingRateT0 + spreadUnlockingRateT1 + spreadUnlockingRateT2;

        vault.increaseSpreadUnlockingTick(t0, spreadUnlockingRateT0);
        vault.increaseSpreadUnlockingTick(t1, spreadUnlockingRateT1);
        vault.increaseSpreadUnlockingTick(t2, spreadUnlockingRateT2);
        vault.increaseSpreadUnlockingRate(spreadUnlockingRate);
        vault.increaseTotalLockedSpread(totalLockedSpread);
    }

    function test_availableAssets_ReturnExpectedValue() public {
        setMaturities();
        addDeposit(users.caller, ud(2e18));

        assertEq(vault.getAvailableAssets(), ud(2e18));

        // (totalAssets - totalLockedSpread) = 1.998
        vault.increaseTotalLockedSpread(ud(0.002e18));
        assertEq(vault.getAvailableAssets(), ud(1.998e18));

        // (totalAssets - totalLockedSpread - totalLockedAssets) = 1.498
        vault.increaseTotalLockedAssets(ud(0.5e18));
        assertEq(vault.getAvailableAssets(), ud(1.498e18));

        // (totalAssets - totalLockedSpread - totalLockedAssets) = 1.298
        vault.increaseTotalLockedSpread(ud(0.2e18));
        assertEq(vault.getAvailableAssets(), ud(1.298e18));

        // (totalAssets - totalLockedSpread - totalLockedAssets) = 1.2979
        vault.increaseTotalLockedAssets(ud(0.0001e18));
        assertEq(vault.getAvailableAssets(), ud(1.2979e18));
    }

    function test_afterBuy_Success() public {
        setupSpreadVault();

        UD60x18 spread = ud(10e18);
        UD60x18 strike = ud(100e18);
        UD60x18 size = ud(1e18);

        assertEq(vault.spreadUnlockingRate(), ud(17744708994708));

        vault.increasePositionSize(t0, strike, ud(1.234e18));

        UD60x18 lockedAmount = isCallTest ? ud(1.234e18) : ud(1.234e18) * strike;
        vault.increaseTotalLockedAssetsNoTransfer(lockedAmount);

        vault.setTimestamp(startTime + 1 days);
        vault.afterBuy(strike, t0, size, spread);

        // lastSpreadUnlockUpdate should equal the time we executed afterBuy as we updated the state there
        assertEq(vault.lastSpreadUnlockUpdate(), startTime + 1 days);
        assertEq(vault.spreadUnlockingRate(), 37034832451498);
        // positionSize should be incremented by the bought amount and equal 2.234
        assertEq(vault.positionSize(t0, strike), ud(1.234e18) + size);
        // spreadUnlockingTick should be incremented by the spread amount divided by the the time to maturity
        UD60x18 increment = ud(10e18) / ud(6 days * 1e18);
        assertEq(vault.spreadUnlockingTicks(t0), ud(1.24e18) / ud(7 days * 1e18) + increment);

        // totalLockedSpread should be incremented by the spread earned (10) after updating the state
        assertEq(vault.totalLockedSpread(), ud(18e18) - ud(17744708994708) * ud(1 days * 1e18) + spread);

        assertEq(vault.getLastTradeTimestamp(), startTime + 1 days);
        assertEq(vault.totalLockedAssets(), (isCallTest ? size : size * strike) + lockedAmount);
    }

    function test_settleMaturity_Success() public {
        t0 = 1676620800;
        t1 = 1677225600;

        UD60x18 size = ud(2e18);
        UD60x18 strike1 = ud(1000e18);
        UD60x18 strike2 = ud(2000e18);

        UD60x18 deposit = isCallTest ? ud(10e18) : ud(10000e18);

        addDeposit(users.caller, deposit);
        assertEq(vault.totalAssets(), scaleDecimals(deposit));

        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](2);

        infos[0].maturity = t0;
        infos[0].strikes = new UD60x18[](2);
        infos[0].sizes = new UD60x18[](2);
        infos[0].strikes[0] = strike1;
        infos[0].strikes[1] = strike2;
        infos[0].sizes[0] = size;
        infos[0].sizes[1] = size;

        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](1);
        infos[1].sizes = new UD60x18[](1);
        infos[1].strikes[0] = strike1;
        infos[1].sizes[0] = size;

        vault.setListingsAndSizes(infos);

        poolKey.maturity = t0;
        poolKey.strike = strike1;
        factory.deployPool{value: 1 ether}(poolKey);

        poolKey.maturity = t0;
        poolKey.strike = strike2;
        factory.deployPool{value: 1 ether}(poolKey);

        poolKey.maturity = t1;
        poolKey.strike = strike1;
        factory.deployPool{value: 1 ether}(poolKey);

        oracleAdapter.setQuoteFrom(t0, ud(1500e18));

        vm.startPrank(users.caller);
        vault.mintFromPool(strike1, t0, size);
        vault.mintFromPool(strike2, t0, size);
        vault.mintFromPool(strike1, t1, size);

        UD60x18 lockedAssets = isCallTest ? ud(6e18) : ud(8000e18);
        assertEq(vault.totalLockedAssets(), lockedAssets);

        UD60x18 assetsAfterMint = isCallTest ? ud(9.982e18) : ud(9976e18);
        assertEq(vault.totalAssets(), scaleDecimals(assetsAfterMint));

        vm.warp(t0);
        vault.settleMaturity(t0);

        assertApproxEqAbs(
            vault.totalAssets(),
            scaleDecimals(isCallTest ? ud(9.3153333e18) : ud(8976e18)),
            0.0000001e18
        );

        assertEq(vault.totalLockedAssets(), isCallTest ? ud(2e18) : ud(2000e18));
    }

    function test_settle_Success() public {
        startTime = 1678435200 + 500 * 7 days;
        t0 = startTime + 7 days;
        t1 = startTime + 14 days;
        t2 = startTime + 21 days;

        vm.warp(startTime);
        UD60x18 totalAssets = isCallTest ? ud(100.03e18) : ud(100000e18);

        if (!isCallTest)
            deal(
                quote,
                users.caller,
                OptionMath.scaleDecimals(totalAssets.unwrap(), 18, ISolidStateERC20(quote).decimals())
            );

        UD60x18 strikeT0_0 = ud(1000e18);
        UD60x18 strikeT0_1 = ud(2000e18);
        UD60x18 strikeT1_0 = ud(1800e18);
        UD60x18 strikeT2_0 = ud(1200e18);
        UD60x18 strikeT2_1 = ud(1300e18);
        UD60x18 strikeT2_2 = ud(2000e18);

        UnderwriterVaultMock.MaturityInfo[] memory infos = new UnderwriterVaultMock.MaturityInfo[](3);

        infos[0].maturity = t0;
        infos[0].strikes = new UD60x18[](2);
        infos[0].sizes = new UD60x18[](2);
        infos[0].strikes[0] = strikeT0_0;
        infos[0].strikes[1] = strikeT0_1;
        infos[0].sizes[0] = ud(2e18);
        infos[0].sizes[1] = ud(1e18);

        infos[1].maturity = t1;
        infos[1].strikes = new UD60x18[](1);
        infos[1].sizes = new UD60x18[](1);
        infos[1].strikes[0] = strikeT1_0;
        infos[1].sizes[0] = ud(1e18);

        infos[2].maturity = t2;
        infos[2].strikes = new UD60x18[](3);
        infos[2].sizes = new UD60x18[](3);
        infos[2].strikes[0] = strikeT2_0;
        infos[2].strikes[1] = strikeT2_1;
        infos[2].strikes[2] = strikeT2_2;
        infos[2].sizes[0] = ud(2e18);
        infos[2].sizes[1] = ud(3e18);
        infos[2].sizes[2] = ud(1e18);

        oracleAdapter.setQuoteFrom(t0, ud(1500e18));
        oracleAdapter.setQuoteFrom(t1, ud(1500e18));
        oracleAdapter.setQuoteFrom(t2, ud(1500e18));

        addDeposit(users.caller, totalAssets);
        vault.setListingsAndSizes(infos);

        for (uint256 i = 0; i < infos.length; i++) {
            for (uint256 j = 0; j < infos[i].strikes.length; j++) {
                poolKey.maturity = infos[i].maturity;
                poolKey.strike = infos[i].strikes[j];

                factory.deployPool{value: 1 ether}(poolKey);

                vm.prank(users.caller);
                vault.mintFromPool(infos[i].strikes[j], infos[i].maturity, infos[i].sizes[j]);
            }
        }

        UD60x18 totalLocked = isCallTest ? ud(10e18) : ud(14100e18);
        assertEq(vault.totalLockedAssets(), totalLocked);

        // setup spread to check that _updateState is called whenever options are settled
        // note: we are not adding the spreads to the balanceOf
        // as we just want to test wif the options are settled correctly
        // we also only test whether the lastSpreadUnlockUpdate was stored correctly
        // to check that the function was called
        vault.setLastSpreadUnlockUpdate(startTime);

        UD60x18 spreadUnlockingRateT1 = ud(1e18) / ud(2e18 * 7 days);
        UD60x18 spreadUnlockingRateT2 = ud(11.2e18) / ud(3e18 * 7 days);

        vault.increaseSpreadUnlockingTick(t1, spreadUnlockingRateT1);
        vault.increaseSpreadUnlockingTick(t2, spreadUnlockingRateT2);
        vault.increaseSpreadUnlockingRate(spreadUnlockingRateT1 + spreadUnlockingRateT2);
        vault.increaseTotalLockedSpread(ud(1e18 + 11.2e18));

        uint256[7] memory timestamps = [t0 - 1 days, t0, t0 + 1 hours, t1, t1 + 1 hours, t2, t2 + 1 hours];

        uint256[7] memory minMaturity = [t0, t1, t1, t2, t2, 0, 0];
        uint256[7] memory maxMaturity = [t2, t2, t2, t2, t2, 0, 0];

        UD60x18[7] memory newLocked = isCallTest
            ? [ud(10e18), ud(7e18), ud(7e18), ud(6e18), ud(6e18), ud(0), ud(0)]
            : [ud(14100e18), ud(10100e18), ud(10100e18), ud(8300e18), ud(8300e18), ud(0), ud(0)];

        UD60x18[7] memory newTotalAssets = isCallTest
            ? [
                ud(100e18),
                ud(99.333333e18),
                ud(99.333333e18),
                ud(99.333333e18),
                ud(99.333333e18),
                ud(98.533333e18),
                ud(98.533333e18)
            ]
            : [
                ud(99957.7e18),
                ud(99457.7e18),
                ud(99457.7e18),
                ud(99157.7e18),
                ud(99157.7e18),
                ud(98657.7e18),
                ud(98657.7e18)
            ];

        uint256 snapshot = vm.snapshot();
        for (uint256 i = 0; i < timestamps.length; i++) {
            vm.warp(timestamps[i]);
            vault.setTimestamp(timestamps[i]);
            vault.settle();
            uint256 delta = isCallTest ? 0.00001e18 : 0;

            assertApproxEqAbs(scaleDecimals(vault.totalAssets()).unwrap(), newTotalAssets[i].unwrap(), delta);
            assertEq(vault.totalLockedAssets(), newLocked[i]);
            assertEq(vault.minMaturity(), minMaturity[i]);
            assertEq(vault.maxMaturity(), maxMaturity[i]);

            if (timestamps[i] == t0 || timestamps[i] == t1 || timestamps[i] == t2) {
                UD60x18[] memory strikes;
                if (timestamps[i] == t0) {
                    strikes = infos[0].strikes;
                } else if (timestamps[i] == t1) {
                    strikes = infos[1].strikes;
                } else if (timestamps[i] == t2) {
                    strikes = infos[2].strikes;
                }

                for (uint256 j = 0; j < strikes.length; j++) {
                    assertEq(vault.positionSize(timestamps[i], strikes[j]), 0);
                }
            }

            assertEq(vault.lastSpreadUnlockUpdate(), timestamps[i]);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_getLockedSpreadInternal_ReturnExpectedValue() public {
        setupSpreadVault();

        uint256[6] memory timestamps = [startTime + 1 days, t0, t0 + 1 days, t1, t1 + 1 days, t2];

        UD60x18[6] memory totalLockSpreads = [
            ud(16.4668e18),
            ud(7.268e18),
            ud(5.912e18),
            ud(3.2e18),
            ud(2.4e18),
            ud(0.0e18)
        ];

        UD60x18[6] memory spreadUnlockingRates = [
            ud(0.0000177447e18),
            ud(0.00001569444e18),
            ud(0.00001569444e18),
            ud(0.00000925925e18),
            ud(0.00000925925e18),
            ud(0.0e18)
        ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < timestamps.length; i++) {
            vault.setTimestamp(timestamps[i]);
            IUnderwriterVault.LockedSpreadInternal memory lockSpread = vault.getLockedSpreadInternal();

            assertApproxEqAbs(lockSpread.totalLockedSpread.unwrap(), totalLockSpreads[i].unwrap(), 0.001e18);
            assertApproxEqAbs(
                lockSpread.spreadUnlockingRate.unwrap(),
                spreadUnlockingRates[i].unwrap(),
                0.0000000001e18
            );
            assertEq(lockSpread.lastSpreadUnlockUpdate, timestamps[i]);

            assertEq(vault.totalLockedSpread(), 18e18);
            assertApproxEqAbs(vault.spreadUnlockingRate().unwrap(), 0.0000177447e18, 0.0000000001e18);
            assertEq(vault.lastSpreadUnlockUpdate(), startTime);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_updateState_Success() public {
        setupSpreadVault();

        uint256[6] memory timestamps = [startTime + 1 days, t0, t0 + 1 days, t1, t1 + 1 days, t2];

        UD60x18[6] memory totalLockSpreads = [
            ud(16.4668e18),
            ud(7.268e18),
            ud(5.912e18),
            ud(3.2e18),
            ud(2.4e18),
            ud(0.0e18)
        ];

        UD60x18[6] memory spreadUnlockingRates = [
            ud(0.0000177447e18),
            ud(0.00001569444e18),
            ud(0.00001569444e18),
            ud(0.00000925925e18),
            ud(0.00000925925e18),
            ud(0.0e18)
        ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < timestamps.length; i++) {
            vault.setTimestamp(timestamps[i]);
            vault.updateState();

            assertApproxEqAbs(vault.totalLockedSpread().unwrap(), totalLockSpreads[i].unwrap(), 0.001e18);
            assertApproxEqAbs(vault.spreadUnlockingRate().unwrap(), spreadUnlockingRates[i].unwrap(), 0.0000000001e18);
            assertEq(vault.lastSpreadUnlockUpdate(), timestamps[i]);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_getPoolAddress_ReturnExpectedValue() public {
        UD60x18 badStrike = ud(100e18);
        uint256 badMaturity = 10000000;

        vm.expectRevert(IVault.Vault__OptionPoolNotListed.selector);
        vault.getPoolAddress(badStrike, poolKey.maturity);

        vm.expectRevert(IVault.Vault__OptionPoolNotListed.selector);
        vault.getPoolAddress(poolKey.strike, badMaturity);

        vm.expectRevert(IVault.Vault__OptionPoolNotListed.selector);
        vault.getPoolAddress(badStrike, badMaturity);

        assertEq(vault.getPoolAddress(poolKey.strike, poolKey.maturity), address(pool));
    }

    function test__revertIfNotTradeableWithVault__Success() public {
        // Does not revert when trying to buy a call option from the call vault
        vault.revertIfNotTradeableWithVault(true, true, true);
        // Does not revert when trying to buy a put option from the put vault
        vault.revertIfNotTradeableWithVault(false, false, true);

        // trying to sell a call option to the call vault
        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.revertIfNotTradeableWithVault(true, true, false);

        // trying to buy a put option from the call vault
        vm.expectRevert(IVault.Vault__OptionTypeMismatchWithVault.selector);
        vault.revertIfNotTradeableWithVault(true, false, true);

        // trying to sell a put option to the call vault
        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.revertIfNotTradeableWithVault(true, false, false);

        // trying to buy a call option from the put vault
        vm.expectRevert(IVault.Vault__OptionTypeMismatchWithVault.selector);
        vault.revertIfNotTradeableWithVault(false, true, true);

        // trying to sell a call option to the put vault
        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.revertIfNotTradeableWithVault(false, true, false);

        // trying to sell a put option to the put vault
        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.revertIfNotTradeableWithVault(false, true, false);
    }

    function test_revertIfOptionInvalid_Success() public {
        vault.setTimestamp(1000);

        // Does not revert when trading a valid option
        vault.revertIfOptionInvalid(ud(1500e18), 1200);

        // trading an expired option
        vm.expectRevert(abi.encodeWithSelector(IVault.Vault__OptionExpired.selector, 1000, 800));
        vault.revertIfOptionInvalid(ud(1500e18), 800);

        // trading an option with a strike equal to zero
        vm.expectRevert(IVault.Vault__StrikeZero.selector);
        vault.revertIfOptionInvalid(ud(0), 800);

        // trading an option with a strike equal to zero
        vm.expectRevert(IVault.Vault__StrikeZero.selector);
        vault.revertIfOptionInvalid(ud(0), 1200);
    }

    function test_revertIfInsufficientFunds_Success() public {
        // Does not revert when trying to buy 5 call contracts when there is 10 units of collateral available
        callVault.revertIfInsufficientFunds(ud(1500e18), ud(5e18), ud(10e18));

        // Does not revert when trying to buy 5 put contracts when there is 5 units of collateral available
        putVault.revertIfInsufficientFunds(ud(1500e18), ud(5e18), ud(10000e18));

        // trying to buy 10 call contracts when there is 10 units of collateral available
        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        callVault.revertIfInsufficientFunds(ud(1500e18), ud(10e18), ud(10e18));

        // trying to buy 12 call contracts when there is 10 units of collateral available
        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        callVault.revertIfInsufficientFunds(ud(1500e18), ud(12e18), ud(10e18));

        // trying to buy 5 put contracts when there is 5 units of collateral available
        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        putVault.revertIfInsufficientFunds(ud(1500e18), ud(5e18), ud(7500e18));

        // trying to buy 5 put contracts when there is 5 units of collateral available
        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        putVault.revertIfInsufficientFunds(ud(1500e18), ud(5e18), ud(5000e18));
    }

    function test_revertIfOutOfDTEBounds_Success() public {
        // Does not revert when equal to the lower bound
        vault.revertIfOutOfDTEBounds(ud(5e18), ud(5e18), ud(10e18));

        // Does not revert when within the bounds
        vault.revertIfOutOfDTEBounds(ud(7e18), ud(5e18), ud(10e18));

        // Does not revert when equal to the upper bound
        vault.revertIfOutOfDTEBounds(ud(10e18), ud(5e18), ud(10e18));

        // below the lower bound
        vm.expectRevert(IVault.Vault__OutOfDTEBounds.selector);
        vault.revertIfOutOfDTEBounds(ud(3e18), ud(5e18), ud(10e18));

        // above the upper bound
        vm.expectRevert(IVault.Vault__OutOfDTEBounds.selector);
        vault.revertIfOutOfDTEBounds(ud(12e18), ud(5e18), ud(10e18));
    }

    function test_revertIfOutOfDeltaBounds_Success() public {
        // Does not revert when equal to the lower bound
        vault.revertIfOutOfDeltaBounds(ud(5e18), ud(5e18), ud(10e18));

        // Does not revert when within the bounds
        vault.revertIfOutOfDeltaBounds(ud(7e18), ud(5e18), ud(10e18));

        // Does not revert when equal to the upper bound
        vault.revertIfOutOfDeltaBounds(ud(10e18), ud(5e18), ud(10e18));

        // below the lower bound
        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.revertIfOutOfDeltaBounds(ud(3e18), ud(5e18), ud(10e18));

        // above the upper bound
        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.revertIfOutOfDeltaBounds(ud(12e18), ud(5e18), ud(10e18));
    }
}
