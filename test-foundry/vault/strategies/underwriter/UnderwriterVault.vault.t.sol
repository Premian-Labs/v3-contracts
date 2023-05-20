// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

abstract contract UnderwriterVaultVaultTest is UnderwriterVaultDeployTest {
    UD60x18 spot = UD60x18.wrap(1000e18);
    UD60x18 strike = UD60x18.wrap(1100e18);
    uint256 timestamp = 1677225600;
    uint256 maturity = 1677830400;

    function setupGetQuote() internal {
        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(
            base,
            spot,
            strike,
            ud(19178082191780821),
            ud(1.54e18)
        );

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);
    }

    function test_computeCLevel_Success() public {
        UD60x18[6] memory utilisation = [
            ud(0e18),
            ud(0.2e18),
            ud(0.4e18),
            ud(0.6e18),
            ud(0.8e18),
            ud(1e18)
        ];

        UD60x18[6] memory duration = [
            ud(0e18),
            ud(3e18),
            ud(6e18),
            ud(9e18),
            ud(12e18),
            ud(15e18)
        ];

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
                vault.computeCLevel(
                    utilisation[i],
                    duration[i],
                    ud(3e18),
                    ud(1e18),
                    ud(1.2e18),
                    ud(0.005e18)
                ),
                expected[i]
            );
        }
    }

    function test_getQuote_ReturnCorrectQuote() public {
        setupGetQuote();

        assertApproxEqAbs(
            scaleDecimals(vault.getQuote(poolKey, ud(3e18), true)).unwrap(),
            isCallTest ? 0.15828885563446596e18 : 469.9068335343156e18,
            isCallTest ? 0.000001e18 : 0.01e18
        );
    }

    function test_getQuote_RevertIf_NotEnoughAvailableAssets() public {
        setupGetQuote();

        vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
        vault.getQuote(poolKey, ud(6e18), true);
    }

    function test_getQuote_RevertIf_PoolDoesNotExist() public {
        setupGetQuote();

        maturity = 1678435200;
        poolKey.maturity = maturity;

        vm.expectRevert(IVault.Vault__OptionPoolNotListed.selector);
        vault.getQuote(poolKey, ud(3e18), true);
    }

    function test_getQuote_RevertIf_ZeroSize() public {
        setupGetQuote();

        vm.expectRevert(IVault.Vault__ZeroSize.selector);
        vault.getQuote(poolKey, ud(0), true);
    }

    function test_getQuote_RevertIf_ZeroStrike() public {
        setupGetQuote();

        poolKey.strike = ud(0);

        vm.expectRevert(IVault.Vault__StrikeZero.selector);
        vault.getQuote(poolKey, ud(3e18), true);
    }

    function test_getQuote_RevertIf_BuyWithWrongVault() public {
        setupGetQuote();

        poolKey.isCallPool = !poolKey.isCallPool;

        vm.expectRevert(IVault.Vault__OptionTypeMismatchWithVault.selector);
        vault.getQuote(poolKey, ud(3e18), true);
    }

    function test_getQuote_RevertIf_TryingToSellToVault() public {
        setupGetQuote();

        vm.expectRevert(IVault.Vault__TradeMustBeBuy.selector);
        vault.getQuote(poolKey, ud(3e18), false);
    }

    function test_getQuote_RevertIf_TryingToBuyExpiredOption() public {
        setupGetQuote();

        vault.setTimestamp(maturity + 3 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault__OptionExpired.selector,
                1677841200,
                1677830400
            )
        );
        vault.getQuote(poolKey, ud(3e18), true);
    }

    function test_getQuote_RevertIf_TryingToBuyOptionNotWithinDTEBounds()
        public
    {
        timestamp = 1676620800;
        maturity = 1682668800;

        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(
            base,
            spot,
            strike,
            ud(19178082191780821),
            ud(1.54e18)
        );
        volOracle.setVolatility(
            base,
            spot,
            strike,
            ud(134246575342465753),
            ud(1.54e18)
        );

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDTEBounds.selector);
        vault.getQuote(poolKey, ud(3e18), true);
    }

    function test_getQuote_RevertIf_TryingToBuyOptionNotWithinDeltaBounds()
        public
    {
        timestamp = 1677225600;
        maturity = 1677830400;
        strike = ud(1500e18);

        poolKey.maturity = maturity;
        poolKey.strike = strike;
        factory.deployPool{value: 1 ether}(poolKey);

        uint256 lastTradeTimestamp = timestamp - 3 hours;
        vault.setLastTradeTimestamp(lastTradeTimestamp);

        oracleAdapter.setQuote(spot);
        volOracle.setVolatility(
            base,
            spot,
            strike,
            ud(19178082191780821),
            ud(1.54e18)
        );

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike;
        addDeposit(users.lp, depositSize);

        vault.setTimestamp(timestamp);
        vault.setSpotPrice(spot);

        vm.expectRevert(IVault.Vault__OutOfDeltaBounds.selector);
        vault.getQuote(poolKey, ud(3e18), true);
    }
}
