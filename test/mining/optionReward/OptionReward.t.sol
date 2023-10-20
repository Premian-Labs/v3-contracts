// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import {IERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/IERC1155BaseInternal.sol";

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {IOptionReward} from "contracts/mining/optionReward/IOptionReward.sol";
import {OptionReward} from "contracts/mining/optionReward/OptionReward.sol";
import {IOptionRewardFactory} from "contracts/mining/optionReward/IOptionRewardFactory.sol";
import {OptionRewardStorage} from "contracts/mining/optionReward/OptionRewardStorage.sol";
import {OptionRewardFactory} from "contracts/mining/optionReward/OptionRewardFactory.sol";

import {OracleAdapterMock} from "contracts/test/adapter/OracleAdapterMock.sol";

import {PaymentSplitter} from "contracts/mining/PaymentSplitter.sol";

import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";

import {IOptionPSFactory} from "contracts/mining/optionPS/IOptionPSFactory.sol";
import {OptionPSFactory} from "contracts/mining/optionPS/OptionPSFactory.sol";
import {IOptionPS} from "contracts/mining/optionPS/IOptionPS.sol";
import {OptionPS} from "contracts/mining/optionPS/OptionPS.sol";
import {OptionPSStorage} from "contracts/mining/optionPS/OptionPSStorage.sol";
import {IMiningAddRewards} from "contracts/mining/IMiningAddRewards.sol";

import {Assertions} from "../../Assertions.sol";

contract MiningMock is IMiningAddRewards {
    address internal immutable PREMIA;

    constructor(address premia) {
        PREMIA = premia;
    }

    function addRewards(uint256 amount) external {
        IERC20(PREMIA).transferFrom(msg.sender, address(this), amount);
    }
}

contract OptionRewardTest is Assertions, Test {
    UD60x18 internal constant discount = UD60x18.wrap(0.55e18);
    UD60x18 internal constant penalty = UD60x18.wrap(0.75e18);
    uint256 internal constant optionDuration = 30 days;
    uint256 internal constant lockupDuration = 365 days;
    uint256 internal constant claimDuration = 365 days;
    UD60x18 internal constant fee = UD60x18.wrap(0.1e18);

    UD60x18 internal spot;

    PaymentSplitter internal paymentSplitter;
    OracleAdapterMock internal oracleAdapter;
    OptionPSFactory internal optionPSFactory;
    OptionReward internal optionReward;
    OptionRewardFactory optionRewardFactory;
    VxPremia internal vxPremia;
    OptionPS internal option;
    address internal mining;

    ERC20Mock internal base;
    ERC20Mock internal quote;

    UD60x18 internal _size;
    uint256 internal size;

    uint64 internal maturity;
    UD60x18 internal strike;

    address internal underwriter;
    address internal otherUnderwriter;
    address internal longReceiver;
    address internal otherLongReceiver;
    address internal feeReceiverOption;
    address internal feeReceiverOptionReward;
    address internal relayer;

    uint256 internal initialBaseBalance;
    uint256 internal initialQuoteBalance;

    function setUp() public {
        maturity = uint64(optionDuration + 8 hours);
        initialBaseBalance = 100e18;
        initialQuoteBalance = 1000e6;
        spot = ud(1e18);
        strike = spot * discount;

        underwriter = vm.addr(1);
        otherUnderwriter = vm.addr(2);
        longReceiver = vm.addr(3);
        otherLongReceiver = vm.addr(4);
        feeReceiverOption = vm.addr(5);
        feeReceiverOptionReward = vm.addr(6);
        relayer = vm.addr(7);

        address optionPSFactoryImpl = address(new OptionPSFactory());
        address optionPSFactoryProxy = address(new ProxyUpgradeableOwnable(optionPSFactoryImpl));
        optionPSFactory = OptionPSFactory(optionPSFactoryProxy);

        address optionPSImpl = address(new OptionPS(feeReceiverOption));
        optionPSFactory.setManagedProxyImplementation(optionPSImpl);

        base = new ERC20Mock("PREMIA", 18);
        quote = new ERC20Mock("USDC", 6);

        size = 100e18;
        _size = ud(size);

        address vxPremiaImpl = address(
            new VxPremia(address(0), address(0), address(base), address(quote), address(0), address(0))
        );
        address vxPremiaProxy = address(new VxPremiaProxy(vxPremiaImpl));
        vxPremia = VxPremia(vxPremiaProxy);

        mining = address(new MiningMock(address(base)));

        paymentSplitter = new PaymentSplitter(base, quote, vxPremia, IMiningAddRewards(mining));

        OracleAdapterMock implementation = new OracleAdapterMock(address(base), address(quote), spot, spot);
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(implementation));
        oracleAdapter = OracleAdapterMock(address(proxy));

        OptionReward optionRewardImplementation = new OptionReward();
        address optionRewardFactoryImpl = address(new OptionRewardFactory(fee, feeReceiverOptionReward));
        ProxyUpgradeableOwnable optionRewardFactoryProxy = new ProxyUpgradeableOwnable(optionRewardFactoryImpl);
        optionRewardFactory = OptionRewardFactory(address(optionRewardFactoryProxy));
        optionRewardFactory.setManagedProxyImplementation(address(optionRewardImplementation));

        option = OptionPS(
            optionPSFactory.deployProxy(
                IOptionPSFactory.OptionPSArgs({base: address(base), quote: address(quote), isCall: true})
            )
        );

        IOptionRewardFactory.OptionRewardKey memory key = IOptionRewardFactory.OptionRewardKey({
            option: option,
            oracleAdapter: oracleAdapter,
            paymentSplitter: paymentSplitter,
            discount: discount,
            penalty: penalty,
            optionDuration: optionDuration,
            lockupDuration: lockupDuration,
            claimDuration: claimDuration,
            fee: fee,
            feeReceiver: feeReceiverOptionReward
        });

        optionReward = OptionReward(optionRewardFactory.deployProxy(key));

        assertTrue(optionRewardFactory.isProxyDeployed(address(optionReward)));
        (address _optionReward, ) = optionRewardFactory.getProxyAddress(key);
        assertEq(address(optionReward), _optionReward);

        address[4] memory users = [underwriter, otherUnderwriter, longReceiver, otherLongReceiver];

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);

            base.mint(users[i], initialBaseBalance);
            base.approve(address(option), initialBaseBalance);
            base.approve(address(optionReward), initialBaseBalance);

            quote.mint(users[i], initialQuoteBalance);
            quote.approve(address(option), initialQuoteBalance);
            quote.approve(address(option), initialQuoteBalance);

            vm.stopPrank();
        }
    }

    function _toTokenDecimals(UD60x18 value, bool isBase) internal pure returns (uint256) {
        uint8 decimals = isBase ? 18 : 6;
        return OptionMath.scaleDecimals(value.unwrap(), 18, decimals);
    }

    function _fromTokenDecimals(uint256 value, bool isBase) internal pure returns (UD60x18) {
        uint8 decimals = isBase ? 18 : 6;
        return ud(OptionMath.scaleDecimals(value, decimals, 18));
    }

    function _longTokenId() internal view returns (uint256) {
        return OptionPSStorage.formatTokenId(IOptionPS.TokenType.Long, maturity, ud(0.55e18));
    }

    function _shortTokenId() internal view returns (uint256) {
        return OptionPSStorage.formatTokenId(IOptionPS.TokenType.Short, maturity, ud(0.55e18));
    }

    function test_deployProxy_RevertIf_ProxyAlreadyDeployed() public {
        IOptionRewardFactory.OptionRewardKey memory key = IOptionRewardFactory.OptionRewardKey({
            option: option,
            oracleAdapter: oracleAdapter,
            paymentSplitter: paymentSplitter,
            discount: discount,
            penalty: penalty,
            optionDuration: optionDuration,
            lockupDuration: lockupDuration,
            claimDuration: claimDuration,
            fee: fee,
            feeReceiver: feeReceiverOptionReward
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IOptionRewardFactory.OptionRewardFactory__ProxyAlreadyDeployed.selector,
                address(optionReward)
            )
        );
        optionReward = OptionReward(optionRewardFactory.deployProxy(key));
    }

    function test_previewOptionParams_Success() public {
        oracleAdapter.setPrice(spot);
        vm.warp(1682155823); // Apr-22-2023 09:30:23 AM +UTC
        uint256 timestamp8AMUTC = 1682150400; // Apr-22-2023 08:00:00 AM +UTC
        uint256 expectedMaturity = timestamp8AMUTC + 30 days; // May-22-2023 08:00:00 AM +UTC
        (UD60x18 _strike, uint64 _maturity) = optionReward.previewOptionParams();
        assertEq(_strike, strike);
        assertEq(_maturity, expectedMaturity);
    }

    function test_underwrite_Success() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        assertEq(option.balanceOf(longReceiver, _longTokenId()), size);
        assertEq(option.balanceOf(longReceiver, _shortTokenId()), 0);
        assertEq(option.balanceOf(address(optionReward), _shortTokenId()), size);
        assertEq(option.balanceOf(address(optionReward), _longTokenId()), 0);

        assertEq(base.balanceOf(underwriter), 0);
        assertEq(base.balanceOf(address(option)), size);
    }

    event Underwrite(address indexed longReceiver, UD60x18 strike, uint64 maturity, UD60x18 contractSize);

    function test_underwrite_CorrectMaturity() public {
        vm.warp(1682155823); // Apr-22-2023 09:30:23 AM +UTC
        oracleAdapter.setPrice(ONE);
        uint256 timestamp8AMUTC = 1682150400; // Apr-22-2023 08:00:00 AM +UTC
        uint256 expectedMaturity = timestamp8AMUTC + 30 days; // May-22-2023 08:00:00 AM +UTC

        vm.expectEmit();
        emit Underwrite(longReceiver, ud(0.55e18), uint64(expectedMaturity), ONE);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE);

        vm.warp(1682207999); // Apr-22-2023 23:59:59 PM +UTC

        expectedMaturity = timestamp8AMUTC + optionDuration; // May-22-2023 08:00:00 AM +UTC
        vm.expectEmit();
        emit Underwrite(longReceiver, ud(0.55e18), uint64(expectedMaturity), ONE);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE);

        vm.warp(1682208000); // Apr-23-2023 00:00:00 AM +UTC

        timestamp8AMUTC = 1682236800; // Apr-23-2023 08:00:00 AM +UTC
        expectedMaturity = timestamp8AMUTC + optionDuration; // May-23-2023 08:00:00 AM +UTC
        vm.expectEmit();
        emit Underwrite(longReceiver, ud(0.55e18), uint64(expectedMaturity), ONE);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE);
    }

    function test_underwrite_RevertIf_PriceIsZero() public {
        oracleAdapter.setPrice(ZERO);

        vm.prank(underwriter);
        vm.expectRevert(IOptionReward.OptionReward__PriceIsZero.selector);
        optionReward.underwrite(longReceiver, _size);
    }

    function test_settle_Success() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.prank(longReceiver);
        UD60x18 exerciseSize = _size / ud(4e18);
        option.exercise(strike, maturity, exerciseSize);

        vm.warp(maturity + 1);

        vm.prank(longReceiver);
        option.settleLong(strike, maturity, exerciseSize);

        optionReward.settle(strike, maturity);

        UD60x18 exerciseCost = (strike * _size) / ud(4e18);

        UD60x18 intrinsicValue = (spot - strike) / spot;
        UD60x18 baseReserved = intrinsicValue * (ONE - penalty) * (_size - exerciseSize);

        assertEq(base.balanceOf(address(mining)), (_size - exerciseSize) - baseReserved);
        assertEq(base.balanceOf(address(optionReward)), baseReserved);
        assertEq(base.balanceOf(longReceiver), initialBaseBalance + exerciseSize.unwrap());
        assertEq(quote.balanceOf(address(vxPremia)), _toTokenDecimals(exerciseCost * (ONE - fee), false));
        assertEq(quote.balanceOf(feeReceiverOptionReward), _toTokenDecimals(exerciseCost * fee, false));

        assertEq(base.balanceOf(address(option)), 0);
        assertEq(quote.balanceOf(address(option)), 0);

        assertEq(option.balanceOf(longReceiver, _longTokenId()), _size - exerciseSize);
        assertEq(option.totalSupply(_shortTokenId()), 0);
    }

    function test_settle_ReserveExcessBaseFromNextSettlement_WhenPartialBaseReserve() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size / ud(10e18));

        vm.prank(otherUnderwriter);
        option.underwrite(strike, maturity, otherLongReceiver, _size);

        spot = spot * ud(10e18);
        oracleAdapter.setPriceAt(maturity, spot);

        vm.prank(otherLongReceiver);
        option.exercise(strike, maturity, _size);

        vm.warp(maturity + 1);

        vm.prank(otherLongReceiver);
        option.settleLong(strike, maturity, _size);

        optionReward.settle(strike, maturity);

        UD60x18 intrinsicValue = (spot - strike) / spot;
        UD60x18 baseReserved = intrinsicValue * (ONE - penalty) * (_size / ud(10e18));

        assertEq(optionReward.getTotalBaseReserved(), baseReserved, "a");
        assertLt(base.balanceOf(address(optionReward)), baseReserved.unwrap()); // There is not enough `base` tokens compared to the expected reserved amount

        spot = spot / ud(10e18);
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size / ud(2e18));

        maturity = 5212800;

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + 1);
        optionReward.settle(strike, maturity);

        assertEq(base.balanceOf(address(optionReward)), optionReward.getTotalBaseReserved()); // We use excess base tokens from this settlement to fill the missing reserve amount
    }

    function test_settle_RevertIf_SettlementAlreadyDone() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + 1);
        optionReward.settle(strike, maturity);

        vm.expectRevert(IOptionReward.OptionReward__InvalidSettlement.selector);
        optionReward.settle(strike, maturity);
    }

    function test_settle_RevertIf_ExercisePeriodNotEnded() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity - 1);
        vm.expectRevert(abi.encodeWithSelector(IOptionReward.OptionReward__OptionNotExpired.selector, maturity));
        optionReward.settle(strike, maturity);
    }

    function test_settle_RevertIf_PriceIsZero() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        vm.warp(maturity + 1);
        vm.expectRevert(IOptionReward.OptionReward__PriceIsZero.selector);
        optionReward.settle(strike, maturity);
    }

    function test_claimRewards_Success() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.prank(longReceiver);
        UD60x18 exerciseSize = _size / ud(4e18);
        option.exercise(strike, maturity, exerciseSize);

        vm.warp(maturity + 1);

        vm.prank(longReceiver);
        option.settleLong(strike, maturity, exerciseSize);
        optionReward.settle(strike, maturity);

        UD60x18 intrinsicValue = spot - strike;
        UD60x18 baseReserved = intrinsicValue * (ONE - penalty) * (_size - exerciseSize);

        vm.warp(maturity + lockupDuration + 1);

        assertEq(option.balanceOf(longReceiver, _longTokenId()), _size - exerciseSize);
        vm.startPrank(longReceiver);
        option.setApprovalForAll(address(optionReward), true);
        optionReward.claimRewards(strike, maturity);
        assertEq(option.balanceOf(longReceiver, _longTokenId()), 0);

        assertEq(base.balanceOf(longReceiver), ud(initialBaseBalance) + exerciseSize + baseReserved);
        assertEq(optionReward.getTotalBaseReserved(), 0);
    }

    function test_claimRewards_RevertIf_LockPeriodNotEnded() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + 1);
        optionReward.settle(strike, maturity);

        vm.warp(maturity + lockupDuration - 1);

        vm.startPrank(longReceiver);
        option.setApprovalForAll(address(optionReward), true);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionReward.OptionReward__LockupNotExpired.selector, maturity + lockupDuration)
        );
        optionReward.claimRewards(strike, maturity);
    }

    function test_claimRewards_RevertIf_ClaimPeriodEnded() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + 1);
        optionReward.settle(strike, maturity);

        vm.warp(maturity + lockupDuration + claimDuration + 1);

        vm.startPrank(longReceiver);
        option.setApprovalForAll(address(optionReward), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOptionReward.OptionReward__ClaimPeriodEnded.selector,
                maturity + lockupDuration + claimDuration
            )
        );
        optionReward.claimRewards(strike, maturity);
    }

    function test_claimRewards_RevertIf_NoErc1155Approval() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + 1);
        optionReward.settle(strike, maturity);

        vm.warp(maturity + lockupDuration + 1);

        vm.startPrank(longReceiver);
        vm.expectRevert(IERC1155BaseInternal.ERC1155Base__NotOwnerOrApproved.selector);
        optionReward.claimRewards(strike, maturity);
    }

    function test_claimRewards_RevertIf_NotEnoughRedeemableLongs() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + 1);
        optionReward.settle(strike, maturity);

        vm.warp(maturity + lockupDuration + 1);

        vm.prank(longReceiver);
        option.safeTransferFrom(longReceiver, otherLongReceiver, _longTokenId(), size, "");

        vm.startPrank(otherLongReceiver);
        option.setApprovalForAll(address(optionReward), true);
        vm.expectRevert(IOptionReward.OptionReward__NoRedeemableLongs.selector);
        optionReward.claimRewards(strike, maturity);
    }

    function test_claimRewards_RevertIf_ZeroRewardPerContract() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.warp(maturity + lockupDuration + 1);

        vm.startPrank(longReceiver);
        option.setApprovalForAll(address(optionReward), true);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionReward.OptionReward__ZeroRewardPerContract.selector, strike, maturity)
        );
        optionReward.claimRewards(strike, maturity);
    }

    function test_getTotalBaseReserved_ReturnExpectedValue() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.prank(longReceiver);
        UD60x18 exerciseSize = _size / ud(4e18);
        option.exercise(strike, maturity, exerciseSize);

        vm.warp(maturity + 1);

        vm.prank(longReceiver);
        option.settleLong(strike, maturity, exerciseSize);
        optionReward.settle(strike, maturity);

        UD60x18 intrinsicValue = spot - strike;
        UD60x18 baseReserved = intrinsicValue * (ONE - penalty) * (_size - exerciseSize);

        assertEq(optionReward.getTotalBaseReserved(), baseReserved);
    }

    function test_releaseRewardsNotClaimed_Success() public {
        oracleAdapter.setPrice(spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, _size);

        oracleAdapter.setPriceAt(maturity, spot);

        vm.prank(longReceiver);
        UD60x18 exerciseSize = _size / ud(4e18);
        option.exercise(strike, maturity, exerciseSize);

        vm.warp(maturity + 1);

        vm.prank(longReceiver);
        option.settleLong(strike, maturity, exerciseSize);
        optionReward.settle(strike, maturity);

        UD60x18 intrinsicValue = spot - strike;
        UD60x18 baseReserved = intrinsicValue * (ONE - penalty) * (_size - exerciseSize);

        vm.warp(maturity + lockupDuration + claimDuration + 1);

        uint256 balance = base.balanceOf(address(mining));
        optionReward.releaseRewardsNotClaimed(strike, maturity);

        assertEq(optionReward.getTotalBaseReserved(), 0);
        assertEq(base.balanceOf(address(mining)), balance + baseReserved.unwrap());
    }

    function test_releaseRewardsNotClaimed_RevertIf_NoBaseReserved() public {
        vm.warp(maturity + lockupDuration + claimDuration + 1);
        vm.expectRevert(abi.encodeWithSelector(IOptionReward.OptionReward__NoBaseReserved.selector, strike, maturity));
        optionReward.releaseRewardsNotClaimed(strike, maturity);
    }
}
