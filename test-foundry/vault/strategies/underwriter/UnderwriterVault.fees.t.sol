// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

abstract contract UnderwriterVaultFeesTest is UnderwriterVaultDeployTest {
    function test_claimFees_TransferProtocolFeesToFeeReceiver() public {
        UD60x18 protocolFees = ud(0.123e18);
        UD60x18 balanceOfFeeReceiver = ud(10.1e18);

        address poolToken = getPoolToken();

        vault.setProtocolFees(protocolFees);
        deal(poolToken, address(vault), scaleDecimals(protocolFees));
        vault.increaseTotalAssets(protocolFees);

        deal(poolToken, feeReceiver, scaleDecimals(balanceOfFeeReceiver));
        vault.claimFees();

        assertEq(
            IERC20(poolToken).balanceOf(feeReceiver),
            scaleDecimals(balanceOfFeeReceiver + protocolFees)
        );
    }

    function test_getAveragePricePerShare_ReturnExpectedValue() public {
        TestVars memory vars;

        vars.shares = ud(1.1e18);
        vars.totalSupply = ud(2.2e18);
        vars.pps = ud(1.0e18);
        vars.ppsUser = ud(1.0e18);

        uint256 snapshot = vm.snapshot();

        setup(vars);
        assertEq(vault.getAveragePricePerShare(users.caller), vars.ppsUser);

        //

        vars.shares = ud(2.3e18);
        vars.totalSupply = ud(2.5e18);
        vars.pps = ud(1.5e18);
        vars.ppsUser = ud(1.2e18);

        vm.revertTo(snapshot);
        setup(vars);
        assertEq(vault.getAveragePricePerShare(users.caller), vars.ppsUser);
    }

    function test_updateTimeOfDeposit_UpdateTimeOfDeposit_ToTimestampOfFirstDeposit()
        public
    {
        uint256 sharesInitial = 0;
        uint256 shareAmount = 1e18;

        vault.mintMock(users.caller, sharesInitial);

        vault.setTimestamp(300000);
        vault.updateTimeOfDeposit(users.caller, sharesInitial, shareAmount);

        assertEq(vault.getTimeOfDeposit(users.caller), 300000);
    }

    function test_updateTimeOfDeposit_UpdateTimeOfDeposit_ToWeightedAvgBasedOnShares()
        public
    {
        uint256 sharesInitial = 2e18;
        uint256 shareAmount = 3e18;
        uint256 timeOfDeposit = 300000;

        vault.mintMock(users.caller, sharesInitial);
        vault.setTimeOfDeposit(users.caller, timeOfDeposit);

        vault.setTimestamp(300000 + 1 days);
        vault.updateTimeOfDeposit(users.caller, sharesInitial, shareAmount);

        assertEq(vault.getTimeOfDeposit(users.caller), 351840);
    }

    function test_getFeeInternal_ReturnExpectedValue() public {
        TestVars memory vars;

        vars.totalSupply = ud(2.2e18);
        vars.shares = ud(1.1e18);
        vars.pps = ud(1.0e18);
        vars.ppsUser = ud(1.0e18);
        vars.performanceFeeRate = ud(0.01e18);
        vars.managementFeeRate = ud(0.02e18);
        vars.timeOfDeposit = 3000000000;
        vars.protocolFeesInitial = ud(0.1e18);
        vars.netUserDepositReceiver = ud(1.2e18);

        uint256 snapshot = vm.snapshot();

        setupGetFeeVars(vars);

        vault.setTimestamp(3000000000 + 1 days);
        IUnderwriterVault.FeeInternal memory feeVars = vault.getFeeInternal(
            users.caller,
            ud(0.1e18),
            vault.getPricePerShare()
        );

        assertEq(feeVars.assets, 0.1e18);
        assertEq(feeVars.balanceShares, 1.1e18);
        assertEq(feeVars.performanceFeeInAssets, 0);
        assertEq(feeVars.managementFeeInAssets, 0.000005479452054794e18);
        assertEq(feeVars.totalFeeInShares, 0.000005479452054794e18);
        assertEq(feeVars.totalFeeInAssets, 0.000005479452054794e18);

        //

        vm.revertTo(snapshot);

        vars.totalSupply = ud(2.5e18);
        vars.shares = ud(2.3e18);
        vars.pps = ud(1.5e18);
        vars.ppsUser = ud(1.2e18);
        vars.performanceFeeRate = ud(0.05e18);
        vars.managementFeeRate = ud(0.02e18);
        vars.timeOfDeposit = 3000000000;
        vars.protocolFeesInitial = ud(0.1e18);
        vars.netUserDepositReceiver = ud(1.2e18);

        setupGetFeeVars(vars);

        vault.setTimestamp(3000000000 + 365 days);
        feeVars = vault.getFeeInternal(
            users.caller,
            ud(1.23e18),
            vault.getPricePerShare()
        );

        assertEq(feeVars.assets, 1.845e18);
        assertEq(feeVars.balanceShares, 2.3e18);
        assertEq(feeVars.performanceFeeInAssets, 0.0230625e18);
        assertEq(feeVars.managementFeeInAssets, 0.0369e18);
        assertEq(feeVars.totalFeeInShares, 0.039975e18);
        assertEq(feeVars.totalFeeInAssets, 0.0599625e18);
    }
}
