import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {Pool_Integration_Shared_Test} from "../shared/Pool.t.sol";

contract Pool_WriteFrom_Concrete_Integration_Test is Pool_Integration_Shared_Test {
    //    function test_writeFrom_Write_500_Options() public givenCallOrPut {
    //        uint256 traderBefore = token.balanceOf(users.trader);
    //        uint256 lpBefore = token.balanceOf(users.lp);
    //
    //        UD60x18 size = ud(500 ether);
    //        uint256 fee = pool.takerFee(users.trader, size, 0, true, false);
    //
    //        changePrank(users.lp);
    //        pool.writeFrom(users.lp, users.trader, size, address(0));
    //
    //        uint256 collateral = toTokenDecimals(contractsToCollateral(size)) + fee;
    //
    //        assertEq(token.balanceOf(address(pool)), collateral);
    //        assertEq(token.balanceOf(users.lp), lpBefore - collateral);
    //
    //        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
    //        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
    //        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
    //        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    //    }
    //
    //    function test_writeFrom_Write_500_Options_WithReferral() public givenCallOrPut {
    //        //uint256 initialCollateral = _mintForLP();
    //
    //        uint256 traderBefore = token.balanceOf(users.trader);
    //        uint256 lpBefore = token.balanceOf(users.lp);
    //
    //        UD60x18 size = ud(500 ether);
    //        uint256 fee = pool.takerFee(users.trader, size, 0, true, false);
    //
    //        changePrank(users.lp);
    //        pool.writeFrom(users.lp, users.trader, size, users.referrer);
    //
    //        uint256 totalRebate;
    //
    //        {
    //            (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);
    //            UD60x18 _primaryRebate = primaryRebatePercent * fromTokenDecimals(fee);
    //            UD60x18 _secondaryRebate = secondaryRebatePercent * fromTokenDecimals(fee);
    //
    //            uint256 primaryRebate = toTokenDecimals(_primaryRebate);
    //            uint256 secondaryRebate = toTokenDecimals(_secondaryRebate);
    //
    //            totalRebate = primaryRebate + secondaryRebate;
    //        }
    //
    //        uint256 collateral = toTokenDecimals(contractsToCollateral(size));
    //
    //        assertEq(token.balanceOf(address(referral)), totalRebate);
    //
    //        assertEq(token.balanceOf(address(pool)), collateral + fee - totalRebate);
    //        assertEq(token.balanceOf(users.lp), lpBefore - collateral - fee);
    //
    //        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
    //        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
    //
    //        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
    //        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    //    }

    function test_writeFrom_Write_500_Options_OnBehalfOfAnotherAddress() public {
        uint256 traderBefore = token.balanceOf(users.trader);
        uint256 lpBefore = token.balanceOf(users.lp);

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true, false);

        changePrank(users.lp);
        setActionAuthorization(users.lp, IUserSettings.Action.WriteFrom, true);

        changePrank(users.operator);
        pool.writeFrom(users.lp, users.trader, size, address(0));

        uint256 collateral = toTokenDecimals(contractsToCollateral(size)) + fee;

        assertEq(token.balanceOf(address(pool)), collateral);
        assertEq(token.balanceOf(users.lp), lpBefore - collateral);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    }
}
