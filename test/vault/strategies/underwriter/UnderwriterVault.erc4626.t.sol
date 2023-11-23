// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";

abstract contract UnderwriterVaultErc4626Test is UnderwriterVaultDeployTest {
    function test_totalAssets_ReturnExpectedValue() public {
        UD60x18[3] memory cases = [ud(1e18), ud(1.1e18), ud(590.7e18)];

        for (uint256 i; i < cases.length; i++) {
            vault.setTotalAssets(cases[i]);
            assertEq(vault.totalAssets(), toTokenDecimals(cases[i]));
        }
    }

    function test_previewWithdraw_ReturnExpectedValue() public {
        UD60x18[4][5] memory cases = [
            [ud(0), ud(0), ud(1e18), ud(1e18)], // [totalSupply, totalAssets, assetAmount, shareAmount]
            [ud(1e18), ud(0), ud(1e18), ud(1e18)],
            [ud(1e18), ud(1e18), ud(1e18), ud(1e18)],
            [ud(4e18), ud(1e18), ud(1e18), ud(4e18)],
            [ud(4e18), ud(5e18), ud(3e18), ud(2.4e18)]
        ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < cases.length; i++) {
            uint256 totalSupply = cases[i][0].unwrap();
            UD60x18 totalAssets = cases[i][1];
            uint256 assetAmount = toTokenDecimals(cases[i][2]);
            UD60x18 shareAmount = cases[i][3];

            vault.setTimestamp(startTime);
            vault.setLastManagementFeeTimestamp(startTime);
            vault.increaseTotalAssets(totalAssets);
            vault.increaseTotalShares(totalSupply);

            if (totalSupply == 0) {
                vm.expectRevert(IVault.Vault__ZeroShares.selector);
                vault.previewWithdraw(assetAmount);
            } else if (totalAssets == ud(0)) {
                vm.expectRevert(IVault.Vault__InsufficientFunds.selector);
                vault.previewWithdraw(assetAmount);
            } else {
                assertEq(vault.previewWithdraw(assetAmount), shareAmount);
            }

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_maxWithdraw_ReturnAvailableAssets() public {
        // should return the available assets since the available assets are less than the max transferable
        setMaturities();
        addDeposit(users.receiver, ud(3e18));

        vault.increaseTotalLockedSpread(ud(0.1e18));
        vault.increaseTotalLockedAssets(ud(0.5e18));

        // incrementing time by a day does not have an effect on the max withdrawable assets
        vault.setTimestamp(block.timestamp + 1 days);
        uint256 assetAmount = vault.maxWithdraw(users.receiver);

        assertEq(assetAmount, toTokenDecimals(ud(2.4e18)));
    }

    function test_maxWithdraw_ReturnMaxTransferableAssets() public {
        setMaturities();

        uint256 snapshot = vm.snapshot();

        addDeposit(users.receiver, ud(2e18));

        vault.setTimestamp(block.timestamp + 1 days);

        uint256 assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, toTokenDecimals(ud(1.999890410958904110e18)));

        vm.revertTo(snapshot);

        addDeposit(users.caller, ud(8e18));
        addDeposit(users.receiver, ud(2e18));

        vault.increaseTotalLockedSpread(ud(0));
        vault.increaseTotalLockedAssets(ud(0.5e18));

        vault.setTimestamp(block.timestamp + 1 days);

        assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, toTokenDecimals(ud(1.999890410958904110e18)));
        vault.increaseTotalLockedAssets(ud(8.0e18));
        assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, toTokenDecimals(ud(1.5 ether)));
    }

    function test_maxWithdraw_ReturnAssetsReceiverOwns() public {
        // should return the assets the receiver owns since there are sufficient funds
        setMaturities();
        addDeposit(users.caller, ud(7e18));
        addDeposit(users.receiver, ud(2e18));
        vault.increaseTotalLockedSpread(ud(0.1e18));
        vault.increaseTotalLockedAssets(ud(0.5e18));
        uint256 assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, toTokenDecimals(ud(1.977777777777777776e18)));
    }

    function test_maxWithdraw_RevertIf_ZeroAddress() public {
        vm.expectRevert(IVault.Vault__AddressZero.selector);
        vault.maxWithdraw(address(0));
    }

    function test_maxRedeem_ReturnAmountOfRedeemableShares() public {
        setMaturities();
        addDeposit(users.receiver, ud(3e18));
        vault.increaseTotalLockedSpread(ud(0.1e18));
        vault.increaseTotalLockedAssets(ud(0.5e18));
        uint256 assetAmount = vault.maxRedeem(users.receiver);
        assertEq(assetAmount, 2.482758620689655174e18);
    }

    function test_maxRedeem_RevertIf_ZeroAddress() public {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));
        vm.expectRevert(IVault.Vault__AddressZero.selector);
        vault.maxRedeem(address(0));
    }

    function test_previewMint_ReturnExpectedValue() public {
        // previewMint should return amount of assets required to mint the amount of shares
        setMaturities();
        assertEq(vault.previewMint(2.1e18), toTokenDecimals(ud(2.1e18)));

        //

        addDeposit(users.receiver, ud(2e18));
        vault.increaseTotalLockedSpread(ud(0.2e18));
        assertEq(vault.previewMint(4e18), toTokenDecimals(ud(3.6e18)));
    }

    function test_convertToShares_MintedShareEqualDepositedAssets_IfNoSharesMinted() public {
        assertEq(vault.convertToShares(toTokenDecimals(ud(2e18))), 2e18);
    }

    function test_convertToShares_MintedSharesEqualsDepositedAssets_IfSupplyNonZero_AndPricePerShareIsOne() public {
        setMaturities();
        addDeposit(users.receiver, ud(8e18));
        assertEq(vault.convertToShares(toTokenDecimals(ud(2e18))), 2e18);
    }

    function test_convertToShares_MintedSharesEqualsDepositedAssets_AdjustedByPricePerShare_IfSupplyNonZero() public {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));

        vault.increaseTotalLockedSpread(ud(1e18));

        assertEq(vault.convertToShares(toTokenDecimals(ud(2e18))), 4e18);
    }

    function test_convertToAssets_WithdrawnAssetsEqualsShareAmount_IfSupplyIsNonZero_AndPricePerShareIsOne() public {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));
        assertEq(vault.convertToAssets(2e18), toTokenDecimals(ud(2e18)));
    }

    function test_convertToAssets_WithdrawnAssetsEqualsHalfOfShareAmount_IfSupplyIsNonZero_AndPricePerShareIsOneHalf()
        public
    {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));
        vault.increaseTotalLockedSpread(ud(1e18));
        assertEq(vault.convertToAssets(2e18), toTokenDecimals(ud(1e18)));
    }

    function test_convertToAssets_RevertIf_SupplyIsZero() public {
        vm.expectRevert(IVault.Vault__ZeroShares.selector);
        vault.convertToAssets(2e18);
    }

    function test_asset_ReturnExpectedValue() public {
        assertEq(vault.asset(), isCallTest ? base : quote);
    }

    function test_deposit_CallsSettle() public {
        IERC20 token = IERC20(getPoolToken());
        uint256 assetAmount = toTokenDecimals(ud(1 ether));

        vm.startPrank(users.trader);

        token.approve(address(vault), assetAmount);
        vm.expectEmit();
        emit UpdateQuotes();
        vault.deposit(assetAmount, users.trader);

        vm.stopPrank();
    }

    function test_withdraw_CallsSettle() public {
        addDeposit(users.trader, ud(1 ether));
        vm.expectEmit();
        emit UpdateQuotes();
        vm.startPrank(users.trader);
        vault.withdraw(isCallTest ? 1 ether : 1e6, users.trader, users.trader);
        vm.stopPrank();
    }

    function test_mint_CallsSettle() public {
        IERC20 token = IERC20(getPoolToken());
        uint256 assetAmount = toTokenDecimals(ud(1 ether));

        vm.startPrank(users.trader);

        token.approve(address(vault), assetAmount);
        uint256 shareAmount = vault.previewDeposit(assetAmount);

        vm.expectEmit();
        emit UpdateQuotes();
        vault.mint(shareAmount, users.trader);

        vm.stopPrank();
    }

    function test_redeem_CallsSettle() public {
        addDeposit(users.trader, ud(1 ether));
        vm.expectEmit();
        emit UpdateQuotes();
        vm.startPrank(users.trader);
        vault.redeem(1 ether, users.trader, users.trader);
        vm.stopPrank();
    }
}
