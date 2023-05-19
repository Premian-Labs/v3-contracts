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
    struct TestResult {
        UD60x18 assets;
        UD60x18 balanceShares;
        UD60x18 performanceFeeInAssets;
        UD60x18 managementFeeInAssets;
        UD60x18 totalFeeInShares;
        UD60x18 totalFeeInAssets;
    }

    function _testCases()
        internal
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

        results[0].assets = ud(0.1e18);
        results[0].balanceShares = ud(1.1e18);
        results[0].performanceFeeInAssets = ud(0);
        results[0].managementFeeInAssets = ud(0.000005479452054794e18);
        results[0].totalFeeInShares = ud(0.000005479452054794e18);
        results[0].totalFeeInAssets = ud(0.000005479452054794e18);

        results[1].assets = ud(1.845e18);
        results[1].balanceShares = ud(2.3e18);
        results[1].performanceFeeInAssets = ud(0.0230625e18);
        results[1].managementFeeInAssets = ud(0.0369e18);
        results[1].totalFeeInShares = ud(0.039975e18);
        results[1].totalFeeInAssets = ud(0.0599625e18);

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

        UD60x18[2] memory transferAmount = [ud(0.1e18), ud(1.23e18)];

        for (uint256 i = 0; i < cases.length; i++) {
            setupGetFeeVars(cases[i]);

            vault.setTimestamp(cases[i].timestamp);
            IUnderwriterVault.FeeInternal memory feeVars = vault.getFeeInternal(
                users.caller,
                transferAmount[i],
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
}
