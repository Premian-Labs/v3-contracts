// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ONE} from "contracts/libraries/Constants.sol";
import {UnderwriterVaultMock} from "contracts/test/vault/strategies/underwriter/UnderwriterVaultMock.sol";
import {IVault} from "contracts/vault/IVault.sol";
import {IUnderwriterVault} from "contracts/vault/strategies/underwriter/IUnderwriterVault.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";

abstract contract UnderwriterVaultFeesTest is UnderwriterVaultDeployTest {
    struct TestResult {
        UD60x18 assets;
        UD60x18 balanceShares;
        UD60x18 performanceFeeInAssets;
        UD60x18 managementFeeInAssets;
        UD60x18 totalFeeInShares;
        UD60x18 totalFeeInAssets;
        UD60x18 sharesAfter;
        UD60x18 protocolFees;
        UD60x18 netUserDepositCallerAfter;
        UD60x18 netUserDepositReceiverAfter;
        uint256 timeOfDepositReceiverAfter;
    }

    function _testCases()
        internal
        pure
        returns (TestVars[2] memory vars, TestResult[2] memory results)
    {
        vars[0].totalSupply = ud(2.2e18);
        vars[0].shares = ud(1.1e18);
        vars[0].pps = ud(1.0e18);
        vars[0].ppsUser = ud(1.0e18);
        vars[0].performanceFeeRate = ud(0.01e18);
        vars[0].managementFeeRate = ud(0.02e18);
        vars[0].timeOfDeposit = 3000000000;
        vars[0].timestamp = 3000000000 + 1 days;
        vars[0].protocolFeesInitial = ud(0.1e18);
        vars[0].netUserDepositReceiver = ud(1.2e18);
        vars[0].transferAmount = ud(0.1e18);

        vars[1].totalSupply = ud(2.5e18);
        vars[1].shares = ud(2.3e18);
        vars[1].pps = ud(1.5e18);
        vars[1].ppsUser = ud(1.2e18);
        vars[1].performanceFeeRate = ud(0.05e18);
        vars[1].managementFeeRate = ud(0.02e18);
        vars[1].timeOfDeposit = 3000000000;
        vars[1].timestamp = 3000000000 + 365 days;
        vars[1].protocolFeesInitial = ud(0.1e18);
        vars[1].netUserDepositReceiver = ud(1.2e18);
        vars[1].transferAmount = ud(1.23e18);

        results[0].assets = ud(0.1e18);
        results[0].balanceShares = ud(1.1e18);
        results[0].performanceFeeInAssets = ud(0);
        results[0].managementFeeInAssets = ud(0.000005479452054794e18);
        results[0].totalFeeInShares = ud(0.000005479452054794e18);
        results[0].totalFeeInAssets = ud(0.000005479452054794e18);
        results[0].sharesAfter = ud(1.0999945204845256e18);
        results[0].protocolFees = ud(0.1e18 + 0.000005479452054794e18);
        results[0].netUserDepositCallerAfter = ud(0.9999945205e18); // 1,1 * 1,0 * ((1,1 - 0,1 - 0,000005479452054794) / 1,1)
        results[0].netUserDepositReceiverAfter = ud(1.3e18);
        results[0].timeOfDepositReceiverAfter = 3000000000 + 1 days;

        results[1].assets = ud(1.845e18);
        results[1].balanceShares = ud(2.3e18);
        results[1].performanceFeeInAssets = ud(0.0230625e18);
        results[1].managementFeeInAssets = ud(0.0369e18);
        results[1].totalFeeInShares = ud(0.039975e18);
        results[1].totalFeeInAssets = ud(0.0599625e18);
        results[1].sharesAfter = ud(2.260025e18);
        results[1].protocolFees = ud(0.1e18 + 0.0599625e18);
        results[1].netUserDepositCallerAfter = ud(1.23603e18); // 2,3 * 1,2 * ((2,3 - 1,23 - 0,039975) / 2,3)
        results[1].netUserDepositReceiverAfter = ud(3.045e18);
        results[1].timeOfDepositReceiverAfter = 3000000000 + 365 days;

        return (vars, results);
    }

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
        (TestVars[2] memory cases, ) = _testCases();

        uint256 snapshot = vm.snapshot();

        for (uint256 i; i < cases.length; i++) {
            setup(cases[i]);
            assertEq(
                vault.getAveragePricePerShare(users.caller),
                cases[i].ppsUser
            );

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
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
        (TestVars[2] memory cases, TestResult[2] memory results) = _testCases();

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < cases.length; i++) {
            setupGetFeeVars(cases[i]);

            vault.setTimestamp(cases[i].timestamp);
            IUnderwriterVault.FeeInternal memory feeVars = vault.getFeeInternal(
                users.caller,
                cases[i].transferAmount,
                vault.getPricePerShare()
            );

            assertEq(feeVars.assets, results[i].assets);
            assertEq(feeVars.balanceShares, results[i].balanceShares);
            assertEq(
                feeVars.performanceFeeInAssets,
                results[i].performanceFeeInAssets
            );
            assertEq(
                feeVars.managementFeeInAssets,
                results[i].managementFeeInAssets
            );
            assertEq(feeVars.totalFeeInShares, results[i].totalFeeInShares);
            assertEq(feeVars.totalFeeInAssets, results[i].totalFeeInAssets);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_getFeeInternal_WithDiscount_ReturnExpectedValue() public {
        (TestVars[2] memory cases, TestResult[2] memory results) = _testCases();

        uint256 snapshot = vm.snapshot();

        UD60x18 discount = ud(vxPremia.getDiscount(users.caller));

        for (uint256 i = 0; i < cases.length; i++) {
            setupGetFeeVars(cases[i]);

            vault.setTimestamp(cases[i].timestamp);
            IUnderwriterVault.FeeInternal memory feeVars = vault.getFeeInternal(
                users.caller,
                cases[i].transferAmount,
                vault.getPricePerShare()
            );

            assertEq(feeVars.assets, results[i].assets);

            assertEq(feeVars.balanceShares, results[i].balanceShares);

            assertEq(
                feeVars.performanceFeeInAssets,
                (ONE - discount) * results[i].performanceFeeInAssets
            );

            assertEq(
                feeVars.managementFeeInAssets,
                (ONE - discount) * results[i].managementFeeInAssets
            );

            assertEq(
                feeVars.totalFeeInShares,
                (ONE - discount) * results[i].totalFeeInShares
            );

            assertEq(
                feeVars.totalFeeInAssets,
                (ONE - discount) * results[i].totalFeeInAssets
            );

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_maxTransferableShares_ReturnExpectedValue() public {
        (TestVars[2] memory _cases, ) = _testCases();

        TestVars[3] memory cases;

        cases[0] = _cases[0];
        cases[1] = _cases[1];

        cases[2].totalSupply = ud(2.2e18);
        cases[2].shares = ud(0);
        cases[2].pps = ud(1.0e18);
        cases[2].ppsUser = ud(1.0e18);
        cases[2].performanceFeeRate = ud(0.01e18);
        cases[2].managementFeeRate = ud(0.02e18);
        cases[2].timeOfDeposit = 3000000000;
        cases[2].timestamp = 3000000000 + 1 days;

        uint256[3] memory results = [
            uint256(1.099939726027397261e18),
            uint256(2.22525e18),
            uint256(0)
        ];

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < cases.length; i++) {
            setupGetFeeVars(cases[i]);

            vault.setTimestamp(cases[i].timestamp);
            IUnderwriterVault.FeeInternal memory feeVars = vault.getFeeInternal(
                users.caller,
                cases[i].shares,
                cases[i].pps
            );

            assertEq(vault.maxTransferableShares(feeVars), results[i]);

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_beforeTokenTransfer_CorrectlyUpdateVariables() public {
        (TestVars[2] memory cases, TestResult[2] memory results) = _testCases();

        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < cases.length; i++) {
            setupBeforeTokenTransfer(cases[i]);
            vm.warp(cases[i].timestamp);

            vault.beforeTokenTransfer(
                users.caller,
                users.receiver,
                cases[i].transferAmount.unwrap()
            );

            assertApproxEqAbs(
                vault.balanceOf(users.caller),
                results[i].sharesAfter.unwrap(),
                1e8
            );
            assertEq(vault.getProtocolFees(), results[i].protocolFees);
            assertEq(vault.getPricePerShare(), cases[i].pps);
            assertApproxEqAbs(
                vault.getNetUserDeposit(users.caller).unwrap(),
                results[i].netUserDepositCallerAfter.unwrap(),
                1e8
            );
            assertApproxEqAbs(
                vault.getNetUserDeposit(users.receiver).unwrap(),
                results[i].netUserDepositReceiverAfter.unwrap(),
                1e8
            );
            assertEq(
                vault.getTimeOfDeposit(users.receiver),
                results[i].timeOfDepositReceiverAfter
            );

            vm.revertTo(snapshot);
            snapshot = vm.snapshot();
        }
    }

    function test_beforeTokenTransfer_NoEffect_IfToAddressZero() public {
        (TestVars[2] memory cases, ) = _testCases();

        setupBeforeTokenTransfer(cases[1]);
        vault.beforeTokenTransfer(
            users.caller,
            address(0),
            cases[1].transferAmount.unwrap()
        );

        assertEq(vault.getNetUserDeposit(address(0)), 0);
        assertEq(vault.getNetUserDeposit(users.caller), 2.76e18);
    }

    function test_beforeTokenTransfer_NoEffect_IfFromAddressZero() public {
        (TestVars[2] memory cases, ) = _testCases();

        setupBeforeTokenTransfer(cases[1]);
        vault.beforeTokenTransfer(
            address(0),
            users.receiver,
            cases[1].transferAmount.unwrap()
        );

        assertEq(vault.getNetUserDeposit(address(0)), 0);
        assertEq(vault.getNetUserDeposit(users.receiver), 1.2e18);
    }

    function test_beforeTokenTransfer_IfReceiverIsVault_DoNotUpdate_NetUserDeposit()
        public
    {
        (TestVars[2] memory cases, TestResult[2] memory results) = _testCases();

        setupBeforeTokenTransfer(cases[1]);
        vm.warp(cases[1].timestamp);
        vault.beforeTokenTransfer(
            users.caller,
            address(vault),
            cases[1].transferAmount.unwrap()
        );

        assertEq(vault.getNetUserDeposit(address(vault)), 0);
        assertApproxEqAbs(
            vault.getNetUserDeposit(users.caller).unwrap(),
            results[1].netUserDepositCallerAfter.unwrap(),
            1e8
        );
    }

    function test_beforeTokenTransfer_RevertIf_TransferAmountTooHigh() public {
        (TestVars[2] memory cases, ) = _testCases();

        setupBeforeTokenTransfer(cases[1]);
        vm.warp(cases[1].timestamp);

        uint256 maxTransferableShares = 2.22525e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault__TransferExceedsBalance.selector,
                2.227354375e18,
                2.23525e18
            )
        );
        vault.beforeTokenTransfer(
            users.caller,
            users.receiver,
            maxTransferableShares + 0.01e18
        );
    }

    function test_afterDeposit_IncrementNetUserDeposits_ByScaledAssetAmount()
        public
    {
        uint256 timestamp = 1000000;
        vault.setTimestamp(timestamp);

        UD60x18 initialAssets = ud(2.5e18);
        UD60x18 initialShares = ud(1.5e18);

        // mock the current user deposits
        vault.mintMock(users.caller, initialShares.unwrap());
        vault.setNetUserDeposit(users.caller, initialAssets.unwrap());
        vault.setTimeOfDeposit(users.caller, timestamp);
        vault.setTotalAssets(initialAssets);

        // increment time and call afterDeposit
        uint256 newlyDepositedAssets = scaleDecimals(ud(3e18));
        uint256 newlyMintedShares = 2e18;
        vault.mintMock(users.caller, newlyMintedShares);
        vault.setTimestamp(timestamp + 7 days);
        vault.afterDeposit(
            users.caller,
            newlyDepositedAssets,
            newlyMintedShares
        );

        assertEq(vault.totalAssets(), scaleDecimals(ud(5.5e18)));
        assertEq(vault.getNetUserDeposit(users.caller), ud(5.5e18));

        // (1.5 * t_0 + 2 * t_1) / 3.5 = (1,5 * 1000000 + 2 * 1604800) / 3,5
        assertEq(vault.getTimeOfDeposit(users.caller), 1345600);
    }

    function test_afterDeposit_RevertIf_ZeroAddress() public {
        vm.expectRevert(IVault.Vault__AddressZero.selector);
        vault.afterDeposit(address(0), 1e18, 1e18);
    }

    function test_afterDeposit_RevertIf_ZeroAssetAmount() public {
        vm.expectRevert(IVault.Vault__ZeroAsset.selector);
        vault.afterDeposit(users.caller, 0, 1e18);
    }

    function test_afterDeposit_RevertIf_ZeroShareAmount() public {
        vm.expectRevert(IVault.Vault__ZeroShares.selector);
        vault.afterDeposit(users.caller, 1e18, 0);
    }

    function test_beforeWithdraw_CallBeforeTokenTransfer_ToTransferPerformanceRelatedFees()
        public
    {
        uint256 timeOfDeposit = 3000000000;
        vault.setManagementFeeRate(ud(0.02e18));
        vault.setPerformanceFeeRate(ud(0.05e18));
        vault.setNetUserDeposit(users.caller, 1.5e18);
        vault.setTimeOfDeposit(users.caller, timeOfDeposit);
        vault.mintMock(users.caller, 1.5e18);
        vault.increaseTotalAssets(ud(3e18));

        assertEq(vault.getPricePerShare(), ud(2e18));

        vault.setTimestamp(timeOfDeposit + (365 days / 2));
        vault.beforeWithdraw(users.caller, scaleDecimals(ud(2e18)), 1e18);

        // performanceFeeInShares = return * fee * share amount = 100% * 0.05 * 1 = 0.05
        // managementFeeInShares = 0.02 * shareAmount * 1 / 2 = 0.01
        // totalFeeInShares = 0.06
        // factor = 1.5 * (1.5 - 1 - 0.06) / 1.5
        // totalFeeInAssets = 0.06 * 2 = 1.2
        // netUserDeposit should decrease proportionally to the shares redeemed + share fees
        assertEq(
            vault.getNetUserDeposit(users.caller),
            0.439999999999999999e18
        );
        // time of deposit should not change on a withdrawal
        assertEq(vault.getTimeOfDeposit(users.caller), timeOfDeposit);

        // check that totalAssets was decreased by the asset amount withdrawn but also by the protocol fees in assets that were charged
        // totalAssets remaining 3 - 2 - 0.12 = 0.88
        assertEq(vault.totalAssets(), scaleDecimals(ud(0.88e18)));
    }

    function test_beforeWithdraw_RevertIf_ZeroAddress() public {
        vm.expectRevert(IVault.Vault__AddressZero.selector);
        vault.beforeWithdraw(address(0), 1e18, 1e18);
    }

    function test_beforeWithdraw_RevertIf_ZeroAssetAmount() public {
        vm.expectRevert(IVault.Vault__ZeroAsset.selector);
        vault.beforeWithdraw(users.caller, 0, 1e18);
    }

    function test_beforeWithdraw_RevertIf_ZeroShareAmount() public {
        vm.expectRevert(IVault.Vault__ZeroShares.selector);
        vault.beforeWithdraw(users.caller, 1e18, 0);
    }
}
