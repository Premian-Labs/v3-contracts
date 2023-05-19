// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

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
            assertEq(vault.totalAssets(), scaleDecimals(cases[i]));
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
            uint256 assetAmount = scaleDecimals(cases[i][2]);
            UD60x18 shareAmount = cases[i][3];

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

        assertEq(assetAmount, scaleDecimals(ud(2.4e18)));
    }

    function test_maxWithdraw_ReturnMaxTransferableAssets() public {
        setMaturities();

        uint256 snapshot = vm.snapshot();

        addDeposit(users.receiver, ud(2e18));

        vault.setTimestamp(block.timestamp + 1 days);

        uint256 assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, scaleDecimals(ud(1.999890410958904110e18)));

        //

        vm.revertTo(snapshot);

        addDeposit(users.caller, ud(8e18));
        addDeposit(users.receiver, ud(2e18));

        vault.increaseTotalLockedSpread(ud(0));
        vault.increaseTotalLockedAssets(ud(0.5e18));

        vault.setTimestamp(block.timestamp + 1 days);

        assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, scaleDecimals(ud(1.999890410958904110e18)));
    }

    function test_maxWithdraw_ReturnAssetsReceiverOwns() public {
        // should return the assets the receiver owns since there are sufficient funds
        setMaturities();
        addDeposit(users.caller, ud(7e18));
        addDeposit(users.receiver, ud(2e18));
        vault.increaseTotalLockedSpread(ud(0.1e18));
        vault.increaseTotalLockedAssets(ud(0.5e18));
        uint256 assetAmount = vault.maxWithdraw(users.receiver);
        assertEq(assetAmount, scaleDecimals(ud(1.977777777777777776e18)));
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

    function test_maxRedeem_ReturnMaxTransferableSharesOfCaller() public {
        // assets caller: 2.3 * 1.5
        // tax caller: 2.3 * 1.5 * 0.05 * 0.25 = 0.43125
        // maxWithdrawable = assets - tax = 3.406875

        TestVars memory vars;

        vars.shares = ud(2.3e18);
        vars.pps = ud(1.5e18);
        vars.ppsUser = ud(1.2e18);
        vars.totalSupply = ud(2.5e18);

        setup(vars);

        vault.setPerformanceFeeRate(ud(0.05e18));
        vault.setManagementFeeRate(ud(0));

        uint256 assetAmount = vault.maxRedeem(users.caller);
        assertEq(assetAmount, 2.27125e18);
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
        assertEq(vault.previewMint(2.1e18), scaleDecimals(ud(2.1e18)));

        //

        addDeposit(users.receiver, ud(2e18));
        vault.increaseTotalLockedSpread(ud(0.2e18));
        assertEq(vault.previewMint(4e18), scaleDecimals(ud(3.6e18)));
    }

    function test_convertToShares_MintedShareEqualDepositedAssets_IfNoSharesMinted()
        public
    {
        assertEq(vault.convertToShares(scaleDecimals(ud(2e18))), 2e18);
    }

    function test_convertToShares_MintedSharesEqualsDepositedAssets_IfSupplyNonZero_AndPricePerShareIsOne()
        public
    {
        setMaturities();
        addDeposit(users.receiver, ud(8e18));
        assertEq(vault.convertToShares(scaleDecimals(ud(2e18))), 2e18);
    }

    function test_convertToShares_MintedSharesEqualsDepositedAssets_AdjustedByPricePerShare_IfSupplyNonZero()
        public
    {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));

        vault.increaseTotalLockedSpread(ud(1e18));

        assertEq(vault.convertToShares(scaleDecimals(ud(2e18))), 4e18);
    }

    function test_convertToAssets_WithdrawnAssetsEqualsShareAmount_IfSupplyIsNonZero_AndPricePerShareIsOne()
        public
    {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));
        assertEq(vault.convertToAssets(2e18), scaleDecimals(ud(2e18)));
    }

    function test_convertToAssets_WithdrawnAssetsEqualsHalfOfShareAmount_IfSupplyIsNonZero_AndPricePerShareIsOneHalf()
        public
    {
        setMaturities();
        addDeposit(users.receiver, ud(2e18));
        vault.increaseTotalLockedSpread(ud(1e18));
        assertEq(vault.convertToAssets(2e18), scaleDecimals(ud(1e18)));
    }

    function test_convertToAssets_RevertIf_SupplyIsZero() public {
        vm.expectRevert(IVault.Vault__ZeroShares.selector);
        vault.convertToAssets(2e18);
    }

    function test_asset_ReturnExpectedValue() public {
        assertEq(vault.asset(), isCallTest ? base : quote);
    }

    function test_transfer_ShouldUpdate_NetUserDeposit_And_TimeOfDeposit()
        public
    {
        TestVars memory vars;
        vars.totalSupply = ud(2.2e18);
        vars.shares = ud(1.1e18);
        vars.pps = ud(1e18);
        vars.ppsUser = ud(1e18);
        vars.performanceFeeRate = ud(0.01e18);
        vars.managementFeeRate = ud(0.02e18);
        vars.timeOfDeposit = 3000000000;
        vars.protocolFeesInitial = ud(0.1e18);
        vars.netUserDepositReceiver = ud(1.2e18);

        setupBeforeTokenTransfer(vars);

        vault.setTimestamp(3000000000 + 1 days);
        vm.prank(users.caller);
        vault.transfer(users.receiver, 0.1e18);

        assertEq(vault.getTimeOfDeposit(users.receiver), 3000000000 + 1 days);
        assertEq(vault.getNetUserDeposit(users.receiver), 1.3e18);
        assertEq(vault.balanceOf(users.receiver), 0.1e18);

        vault.setTimestamp(3000000000 + 366 days);

        vm.prank(users.caller);
        vault.transfer(users.receiver, 0.1e18);

        assertEq(
            vault.getTimeOfDeposit(users.receiver),
            3000000000 + 1 days + (365 days / 2)
        );
        assertEq(vault.getNetUserDeposit(users.receiver), 1.4e18);
        assertEq(vault.balanceOf(users.receiver), 0.2e18);
    }

    function test_deposit_UpdateFeeRelatedNumbers() public {
        TestVars memory vars;
        vars.totalSupply = ud(2.2e18);
        vars.shares = ud(1.1e18);
        vars.pps = ud(1e18);
        vars.ppsUser = ud(1e18);
        vars.performanceFeeRate = ud(0.01e18);
        vars.managementFeeRate = ud(0.02e18);
        vars.timeOfDeposit = 3000000000;
        vars.protocolFeesInitial = ud(0.1e18);
        vars.netUserDepositReceiver = ud(1.2e18);

        setupBeforeTokenTransfer(vars);

        IERC20 token = IERC20(getPoolToken());

        uint256 assetAmount = scaleDecimals(ud(1.4e18));

        vm.startPrank(users.caller);

        deal(address(token), users.caller, assetAmount);
        token.approve(address(vault), assetAmount);
        vault.setTimestamp(3000000000 + 1 days);
        vault.deposit(assetAmount, users.caller);

        // 1.1 + 1.4 = 2.5
        assertEq(vault.getNetUserDeposit(users.caller), 2.5e18);
        // (1.1 * 3000000000 + 1.4 * 3000086400) / 2.5
        assertEq(vault.getTimeOfDeposit(users.caller), 3000048384);
        assertEq(vault.balanceOf(users.caller), 2.5e18);
    }

    function test_withdraw_UpdateFeeRelatedNumbers() public {
        TestVars memory vars;
        vars.totalSupply = ud(2.2e18);
        vars.shares = ud(1.1e18);
        vars.pps = ud(1e18);
        vars.ppsUser = ud(1e18);
        vars.performanceFeeRate = ud(0.01e18);
        vars.managementFeeRate = ud(0.02e18);
        vars.timeOfDeposit = 3000000000;
        vars.protocolFeesInitial = ud(0.1e18);
        vars.netUserDepositReceiver = ud(1.2e18);

        setupBeforeTokenTransfer(vars);

        uint256 assetAmount = scaleDecimals(ud(0.4e18));
        vault.setTimestamp(3000000000 + 1 days);

        vm.prank(users.caller);
        vault.withdraw(assetAmount, users.caller, users.caller);

        assertEq(
            vault.getNetUserDeposit(users.caller),
            0.699978082191780821e18
        );
        assertEq(vault.getTimeOfDeposit(users.caller), 3000000000);
        assertEq(vault.balanceOf(users.caller), 0.699978082191780822e18);
    }
}
