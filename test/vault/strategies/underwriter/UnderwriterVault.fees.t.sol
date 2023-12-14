// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "./UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";
import "forge-std/StdAssertions.sol";

abstract contract UnderwriterVaultFeesTest is UnderwriterVaultDeployTest {
    uint256 timestamp0 = 8000000;
    uint256 timestamp1 = timestamp0 + (365 days) / 2;
    uint256 timestamp2 = timestamp1 + 365 days;

    UD60x18 strike0 = ud(100e18);

    event ManagementFeePaid(address indexed feeReceiver, uint256 feesInSharesMinted);

    function setupManagementFees() public {
        vault.setProtocolFees(ud(0e18));
        vault.setTimestamp(timestamp0);
    }

    function _test_chargeManagementFees_DepositEmptyVault() public {
        setupManagementFees();
        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike0;
        addDeposit(users.lp, depositSize);
        // check that lastManagementFeeTimestamp updates correctly when there are zero totalAssets inside the vault
        assertEq(vault.getLastManagementFeeTimestamp(), timestamp0);
    }

    function test_chargeManagementFees_DepositEmptyVault() public {
        _test_chargeManagementFees_DepositEmptyVault();
    }

    function test_chargeManagementFees_TestFunctionCall() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year
        vault.setTimestamp(timestamp1);
        assertEq(vault.getLastManagementFeeTimestamp(), timestamp0);
        //
        vm.expectEmit();
        UD60x18 feeInShares = isCallTest ? ud(0.050505050505050505e18) : ud(0.050505050505050505e20);
        emit ManagementFeePaid(FEE_RECEIVER, feeInShares.unwrap());
        // test exposed function
        vault.chargeManagementFees();
        assertEq(vault.getLastManagementFeeTimestamp(), timestamp1);
        assertEq(ud(vault.totalAssets()), isCallTest ? ud(5e18) : ud(5e6) * strike0);
        assertEq(vault.getProtocolFees(), ud(0e18)); // protocol fees should not be incremented
        assertEq(vault.totalSupply(), isCallTest ? ud(5.050505050505050505e18) : ud(5.050505050505050505e20));
        assertEq(vault.getPricePerShare(), ud(0.99e18));
        assertEq(vault.balanceOf(FEE_RECEIVER), feeInShares);
    }

    function _test_deposit_ChargeManagementFees() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year
        vault.setTimestamp(timestamp1);

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike0;
        addDeposit(users.lp, depositSize);

        assertEq(vault.getLastManagementFeeTimestamp(), timestamp1);
        assertEq(ud(vault.totalAssets()), isCallTest ? ud(10e18) : ud(10e6) * strike0);
        assertEq(vault.totalSupply(), isCallTest ? ud(10.101010101010101010e18) : ud(10.10101010101010101005e20));
        assertEq(vault.getProtocolFees(), ud(0e18));
        assertEq(vault.getPricePerShare(), ud(0.99e18));
    }

    function test_deposit_ChargeManagementFees() public {
        _test_deposit_ChargeManagementFees();
    }

    function test_mint_ChargeManagementFees() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year
        vault.setTimestamp(timestamp1);

        UD60x18 depositSize = isCallTest ? ud(5e18) : ud(5e18) * strike0;
        addMint(users.lp, depositSize);
        assertEq(vault.getLastManagementFeeTimestamp(), timestamp1);

        assertApproxEqAbs(vault.totalAssets(), isCallTest ? 10e18 : (ud(10e6) * strike0).unwrap(), 1);
        assertEq(vault.totalSupply(), isCallTest ? ud(10.101010101010101010e18) : ud(10.10101010101010101005e20));
        assertEq(vault.getProtocolFees(), ud(0e18));
        assertApproxEqAbs(vault.getPricePerShare().unwrap(), 0.99e18, isCallTest ? 1 : 1e9);
    }

    function test_withdraw_ChargeManagementFees() public {
        _test_deposit_ChargeManagementFees();
        // time travel a year from the current timestamp
        vault.setTimestamp(timestamp2);
        // process a withdraw
        vm.startPrank(users.lp);
        UD60x18 assetAmount = isCallTest ? ud(5e18) : ud(5e6) * strike0;
        vault.withdraw(assetAmount.unwrap(), users.lp, users.lp);
        vm.stopPrank();
        // test correct processing
        assertEq(vault.getLastManagementFeeTimestamp(), timestamp2);
        assertEq(ud(vault.totalAssets()), isCallTest ? ud(5e18) : ud(5e8));
        assertEq(vault.getProtocolFees(), ud(0e18));
        // call: 10,101010101010101010 + 10,101010101010101010 * 0,02 / 0,98 - 5 / 0,9702
        assertEq(vault.totalSupply(), isCallTest ? ud(5.153576582148010715e18) : ud(5.15357658214801071486e20));
        assertEq(vault.getPricePerShare(), ud(0.9702e18));
    }

    function test_redeem_ChargeManagementFees() public {
        _test_deposit_ChargeManagementFees();
        // time travel a year from the current timestamp
        vault.setTimestamp(timestamp2);
        // process a redeem
        vm.startPrank(users.lp);
        UD60x18 assetAmount = isCallTest ? ud(5e18) : ud(5e6) * strike0;
        uint256 shareAmount = vault.previewWithdraw(assetAmount.unwrap());
        vault.redeem(shareAmount, users.lp, users.lp);
        vm.stopPrank();
        // test correct processing
        assertEq(vault.getLastManagementFeeTimestamp(), timestamp2);
        assertApproxEqAbs(vault.totalAssets(), isCallTest ? 5e18 : 5e8, 1);
        assertEq(vault.getProtocolFees(), ud(0e18));
        // call: 10,101010101010101010 + 10,101010101010101010 * 0,02 / 0,98 - 5 / 0,9702
        assertEq(vault.totalSupply(), isCallTest ? ud(5.153576582148010715e18) : ud(5.15357658214801071486e20));
        assertApproxEqAbs(vault.getPricePerShare().unwrap(), 0.9702e18, isCallTest ? 1 : 1e10);
    }

    function test_computeManagementFees_EmptyVault() public {
        setupManagementFees();
        UD60x18 managementFeesInShares = vault.computeManagementFees();
        assertEq(managementFeesInShares, ud(0));
    }

    function test_computeManagementFees_DepositIntoExistingVault() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        UD60x18 managementFeesInShares = vault.computeManagementFees();
        assertEq(
            managementFeesInShares,
            isCallTest ? ud(0.050505050505050505e18) : ud(0.05050505050505050500e18) * strike0
        );
    }

    function test_getPricePerShare_ChargeManagementFees() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        // test explicitly that the management fees are being deducted
        assertEq(vault.getPricePerShare(), ud(0.99e18));
        // time travel a year from the current timestamp
        vault.setTimestamp(timestamp2);
        assertEq(vault.getPricePerShare(), ud(0.97e18));
    }

    function test_previewMint_EmptyVault() public {
        setupManagementFees();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        assertEq(vault.getPricePerShare(), ud(1e18));
        UD60x18 shareAmount = ud(5e18);
        uint256 assetAmount = vault.previewMint(shareAmount.unwrap());
        assertEq(assetAmount, toTokenDecimals(ud(5e18)));
    }

    function test_previewMint_OneDeposit() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        assertEq(vault.getPricePerShare(), ud(0.99e18));
        UD60x18 shareAmount = ud(5e18);
        uint256 assetAmount = vault.previewMint(shareAmount.unwrap());
        assertEq(assetAmount, toTokenDecimals(ud(4.95e18)));
    }

    function test_previewDeposit_EmptyVault() public {
        setupManagementFees();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        assertEq(vault.getPricePerShare(), ud(1e18));
        UD60x18 assetAmount = isCallTest ? ud(5e18) : ud(5e6);
        uint256 shareAmount = vault.previewDeposit(assetAmount.unwrap());
        assertEq(shareAmount, 5e18);
    }

    function test_previewDeposit_OneDeposit() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        assertEq(vault.getPricePerShare(), ud(0.99e18));
        UD60x18 assetAmount = isCallTest ? ud(5e18) : ud(5e6);
        uint256 shareAmount = vault.previewDeposit(assetAmount.unwrap());
        assertApproxEqAbs(shareAmount, ud(5.05050505050505e18).unwrap(), 1e6);
    }

    function test_previewRedeem_NoManagementFees() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // do not time travel such that there are no management fees
        assertEq(vault.getPricePerShare(), ud(1e18));
        uint256 shareAmount = 5e18;
        uint256 assetAmount = vault.previewRedeem(shareAmount);
        assertEq(assetAmount, isCallTest ? 5e18 : 5e6);
    }

    function test_previewRedeem_OneDeposit() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        assertEq(vault.getPricePerShare(), ud(0.99e18));
        uint256 shareAmount = 5e18;
        uint256 assetAmount = vault.previewRedeem(shareAmount);
        assertEq(assetAmount, isCallTest ? 4.95e18 : 4.95e6);
    }

    function test_previewWithdraw_NoManagementFees() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // do not time travel such that there are no management fees
        assertEq(vault.getPricePerShare(), ud(1e18));
        UD60x18 assetAmount = isCallTest ? ud(5e18) : ud(5e6);
        uint256 shareAmount = vault.previewWithdraw(assetAmount.unwrap());
        assertEq(shareAmount, ud(5e18).unwrap());
    }

    function test_previewWithdraw_OneDeposit() public {
        _test_chargeManagementFees_DepositEmptyVault();
        // time travel half a year from the current timestamp
        vault.setTimestamp(timestamp1);
        assertEq(vault.getPricePerShare(), ud(0.99e18));
        UD60x18 assetAmount = isCallTest ? ud(5e18) : ud(5e6);
        uint256 shareAmount = vault.previewWithdraw(assetAmount.unwrap());
        assertApproxEqAbs(shareAmount, ud(5.05050505050505e18).unwrap(), 1e6);
    }

    function test_claimFees_TransferProtocolFeesToFeeReceiver() public {
        UD60x18 protocolFees = ud(0.123e18);
        UD60x18 balanceOfFeeReceiver = ud(10.1e18);

        address poolToken = getPoolToken();

        vault.setProtocolFees(protocolFees);
        deal(poolToken, address(vault), toTokenDecimals(protocolFees));
        vault.increaseTotalAssets(protocolFees);

        deal(poolToken, FEE_RECEIVER, toTokenDecimals(balanceOfFeeReceiver));
        vm.expectEmit();
        emit ClaimProtocolFees(FEE_RECEIVER, toTokenDecimals(protocolFees));
        vault.claimFees();
        assertEq(IERC20(poolToken).balanceOf(FEE_RECEIVER), toTokenDecimals(balanceOfFeeReceiver + protocolFees));
    }
}
